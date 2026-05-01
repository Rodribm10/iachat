"""Captain Webhook Adapter — extends Hermes built-in WebhookAdapter to
support stable session_chat_id derived from a payload field.

Why this exists
---------------
The default ``WebhookAdapter`` builds the session key as::

    session_chat_id = f"webhook:{route_name}:{delivery_id}"

Since ``delivery_id`` is unique per HTTP POST, every webhook hit creates a
fresh Hermes session. That's correct behavior for one-shot webhook events
(GitHub PRs, monitoring alerts) but wrong for backend integrations where
many messages of the same logical conversation must share session memory.

This plugin lets the caller include a stable identifier in the JSON
payload — typically ``conversation_id`` (preferred) or
``hermes_session_id`` — and the adapter rewrites the session key to::

    session_chat_id = f"webhook:{route_name}:session:{conversation_id}"

Same conversation_id across multiple POSTs → same session in Hermes →
session memory preserved. Different conversation_id (or none) → fresh
session, identical to the built-in.

Idempotency (``delivery_id`` based) is unchanged: each POST still gets a
unique delivery_id, so retries are still de-duplicated.

Implementation
--------------
We register this plugin under the SAME platform name as the built-in
(``webhook``). Hermes' ``_create_adapter`` checks ``platform_registry``
first and uses the plugin if registered, falling back to the built-in
only if nothing is registered. So registering ``name="webhook"`` here
substitutes the built-in completely.

Behavior is inherited unchanged from ``WebhookAdapter`` (HMAC, rate
limiting, idempotency, signature validation, prompt rendering, deliver
dispatch). The only override is ``handle_message()``, which mutates
``event.source.chat_id`` before delegating to the parent.
"""

import logging
from typing import Optional

from gateway.platforms.base import MessageEvent
from gateway.platforms.webhook import WebhookAdapter

logger = logging.getLogger(__name__)


class CaptainWebhookAdapter(WebhookAdapter):
    """WebhookAdapter with stable session_chat_id derived from payload."""

    SESSION_FIELD_PRIMARY = "hermes_session_id"
    SESSION_FIELD_FALLBACK = "conversation_id"

    async def connect(self) -> bool:
        # Hermes' built-in webhook adapter is the only platform that gets
        # `gateway_runner` set explicitly in `_create_adapter()` (see
        # gateway/run.py around `Platform.WEBHOOK`). When a plugin replaces
        # the built-in via `platform_registry`, that explicit assignment is
        # skipped — leaving `self.gateway_runner` unset and breaking
        # cross-platform delivery (e.g. forwarding the response to a sibling
        # plugin like `http_callback`).
        #
        # Recover by pulling the live runner from the module-level
        # `_gateway_runner_ref` weakref that GatewayRunner.__init__ populates.
        if not getattr(self, "gateway_runner", None):
            try:
                from gateway.run import _gateway_runner_ref
                runner = _gateway_runner_ref()
                if runner is not None:
                    self.gateway_runner = runner
                    logger.info(
                        "[captain-webhook] gateway_runner linked via _gateway_runner_ref"
                    )
                else:
                    logger.warning(
                        "[captain-webhook] _gateway_runner_ref() returned None — "
                        "cross-platform delivery (http_callback etc) will fail"
                    )
            except Exception as exc:  # pragma: no cover - defensive
                logger.warning(
                    "[captain-webhook] Could not link gateway_runner: %s", exc
                )
        return await super().connect()

    async def handle_message(self, event: MessageEvent) -> None:
        custom_session = self._extract_custom_session_id(event)
        if custom_session:
            self._rewrite_chat_id(event, custom_session)
        return await super().handle_message(event)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _extract_custom_session_id(self, event: MessageEvent) -> Optional[str]:
        payload = event.raw_message
        if not isinstance(payload, dict):
            return None
        value = payload.get(self.SESSION_FIELD_PRIMARY) or payload.get(
            self.SESSION_FIELD_FALLBACK
        )
        if value is None:
            return None
        return str(value).strip() or None

    def _rewrite_chat_id(self, event: MessageEvent, custom_session: str) -> None:
        old_chat_id = event.source.chat_id
        # Default chat_id format from base WebhookAdapter:
        #   "webhook:<route_name>:<delivery_id>"
        # Extract route_name to keep the new key consistent with that scheme.
        try:
            prefix, route_name, _ = old_chat_id.split(":", 2)
        except ValueError:
            logger.warning(
                "[captain-webhook] Unexpected chat_id format %r — skipping rewrite",
                old_chat_id,
            )
            return

        new_chat_id = f"{prefix}:{route_name}:session:{custom_session}"
        if new_chat_id == old_chat_id:
            return

        # The base adapter stores delivery info under the original chat_id so
        # that send() can locate the deliver target/payload when the agent
        # finishes. Mirror the entry under the new chat_id so the rewrite
        # doesn't break delivery routing.
        delivery_config = self._delivery_info.get(old_chat_id)
        if delivery_config is not None:
            self._delivery_info[new_chat_id] = delivery_config
            self._delivery_info_created[new_chat_id] = (
                self._delivery_info_created.get(old_chat_id, 0)
            )

        # SessionSource and MessageEvent are non-frozen dataclasses — safe to mutate.
        event.source.chat_id = new_chat_id

        logger.info(
            "[captain-webhook] Stable session: %s -> %s (custom=%s)",
            old_chat_id,
            new_chat_id,
            custom_session,
        )


# ---------------------------------------------------------------------------
# Plugin registry hooks
# ---------------------------------------------------------------------------

def check_requirements() -> bool:
    """Built-in WebhookAdapter must be importable (it always is in Hermes)."""
    try:
        from gateway.platforms.webhook import WebhookAdapter  # noqa: F401
        return True
    except ImportError:
        return False


def validate_config(config) -> bool:  # pragma: no cover - trivial passthrough
    """All built-in webhook config is valid for this adapter as well."""
    return True


def is_connected(config) -> bool:  # pragma: no cover - trivial passthrough
    """Always considered ready when the platform block is enabled."""
    extra = getattr(config, "extra", {}) or {}
    return bool(extra.get("enabled", True))


def register(ctx) -> None:
    """Plugin entry point.

    Registers under name="webhook" — same as the built-in — so Hermes'
    ``_create_adapter`` picks this adapter instead of the built-in
    (registry is checked before the if/elif chain).
    """
    ctx.register_platform(
        name="webhook",
        label="Captain Webhook (stable sessions)",
        adapter_factory=lambda cfg: CaptainWebhookAdapter(cfg),
        check_fn=check_requirements,
        validate_config=validate_config,
        is_connected=is_connected,
        required_env=[],
        install_hint="Inherits from built-in WebhookAdapter — no extra deps.",
        emoji="🪝",
        pii_safe=True,
        allow_update_command=False,
        platform_hint=(
            "Webhook platform with stable session_chat_id when payload "
            "carries 'conversation_id' or 'hermes_session_id'. Keeps the "
            "same Hermes session across multiple HTTP POSTs of the same "
            "logical conversation."
        ),
    )
