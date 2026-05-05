"""HTTP Callback Platform Adapter for Hermes Agent.

A plugin-based gateway adapter that delivers the agent response as an HTTP
POST to a configurable URL — instead of pushing it to a chat platform.

Designed for backend integrations (e.g. Captain / Chatwoot ↔ Hermes) where
the response must be returned synchronously to a known service endpoint.

Usage:

    hermes webhook subscribe my-route \\
        --deliver http_callback \\
        --deliver-chat-id "http://your-backend/api/hermes_callback"

The URL passed via ``--deliver-chat-id`` is what receives the POST when the
agent finishes processing the inbound webhook.

Environment variables:
    CAPTAIN_HTTP_CALLBACK_SECRET   Optional HMAC-SHA256 signing key. When set,
                                   each POST includes header
                                   ``X-Hermes-Callback-Signature: sha256=<hex>``
                                   computed over the raw request body.
"""

import asyncio
import hashlib
import hmac
import json
import logging
import os
import time
from typing import Any, AsyncIterator, Dict, Optional

import aiohttp

from gateway.config import Platform
from gateway.platforms.base import BasePlatformAdapter, MessageEvent, SendResult

logger = logging.getLogger(__name__)


class HttpCallbackAdapter(BasePlatformAdapter):
    """Send-only adapter that POSTs the agent response to an HTTP URL.

    Inbound message reception is NOT supported — this adapter is meant to
    pair with the built-in ``webhook`` adapter (which receives requests and
    invokes the agent). The flow is:

        external service -> POST /webhooks/<route> (webhook adapter)
                         -> agent processes
                         -> http_callback adapter POSTs response back
    """

    def __init__(self, config, **kwargs):
        platform = Platform("http_callback")
        super().__init__(config=config, platform=platform)

        extra = getattr(config, "extra", {}) or {}
        self.signing_secret: str = (
            os.getenv("CAPTAIN_HTTP_CALLBACK_SECRET")
            or extra.get("signing_secret", "")
        )
        self.timeout_seconds: float = float(extra.get("timeout_seconds", 15))
        self._session: Optional[aiohttp.ClientSession] = None

    # ------------------------------------------------------------------ lifecycle
    async def connect(self) -> bool:
        """Open a reusable aiohttp session — no real network handshake."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=self.timeout_seconds),
            )
        logger.info(
            "[http_callback] adapter ready (signing=%s, timeout=%.1fs)",
            "yes" if self.signing_secret else "no",
            self.timeout_seconds,
        )
        return True

    async def disconnect(self) -> None:
        if self._session is not None and not self._session.closed:
            await self._session.close()
        self._session = None

    # ------------------------------------------------------------------ send
    async def send(
        self,
        chat_id: str,
        content: str,
        reply_to: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> SendResult:
        """POST the agent response to ``chat_id`` (interpreted as a URL)."""
        url = (chat_id or "").strip()
        if not url.startswith(("http://", "https://")):
            return SendResult(
                success=False,
                error=f"Invalid callback URL: {url!r} (must start with http:// or https://)",
            )

        body: Dict[str, Any] = {
            "content": content,
            "reply_to": reply_to,
            "metadata": metadata or {},
            "timestamp": int(time.time()),
        }
        body_bytes = json.dumps(body, ensure_ascii=False).encode("utf-8")

        headers = {"Content-Type": "application/json; charset=utf-8"}
        if self.signing_secret:
            sig = hmac.new(
                self.signing_secret.encode("utf-8"),
                body_bytes,
                hashlib.sha256,
            ).hexdigest()
            headers["X-Hermes-Callback-Signature"] = f"sha256={sig}"

        if self._session is None or self._session.closed:
            await self.connect()

        try:
            async with self._session.post(url, data=body_bytes, headers=headers) as resp:
                status = resp.status
                resp_text = await resp.text()
                if 200 <= status < 300:
                    logger.info("[http_callback] POST %s -> HTTP %d", url, status)
                    return SendResult(
                        success=True,
                        message_id=f"hcb-{int(time.time() * 1000)}",
                    )
                logger.warning(
                    "[http_callback] POST %s -> HTTP %d (body[:200]=%r)",
                    url,
                    status,
                    resp_text[:200],
                )
                return SendResult(
                    success=False,
                    error=f"HTTP {status}: {resp_text[:200]}",
                )
        except asyncio.TimeoutError:
            return SendResult(
                success=False,
                error=f"Timeout after {self.timeout_seconds}s",
            )
        except aiohttp.ClientError as e:
            logger.exception("[http_callback] aiohttp error for %s", url)
            return SendResult(success=False, error=f"{type(e).__name__}: {e}")
        except Exception as e:  # pylint: disable=broad-except
            logger.exception("[http_callback] unexpected error for %s", url)
            return SendResult(success=False, error=f"{type(e).__name__}: {e}")

    # ------------------------------------------------------------------ no-op
    async def send_typing(self, chat_id: str, metadata=None) -> None:  # noqa: D401
        """No-op — HTTP callback has no typing indicator."""
        return None

    async def get_chat_info(self, chat_id: str) -> Dict[str, Any]:
        return {
            "chat_id": chat_id,
            "platform": "http_callback",
            "type": "http_callback",
        }

    async def receive_messages(self) -> AsyncIterator[MessageEvent]:
        """Adapter is send-only — never yields events."""
        if False:  # pragma: no cover - never executed; keeps async generator typing
            yield  # type: ignore[misc]
        return


# ---------------------------------------------------------------------------
# Plugin registry hooks
# ---------------------------------------------------------------------------

def check_requirements() -> bool:
    """``aiohttp`` ships with Hermes — should always be importable."""
    try:
        import aiohttp  # noqa: F401
        return True
    except ImportError:
        return False


def validate_config(config) -> bool:  # pragma: no cover - trivial
    """No global config required — URL comes per-subscription via chat_id."""
    return True


def is_connected(config) -> bool:  # pragma: no cover - trivial
    """Always considered ready (no persistent connection)."""
    return True


def register(ctx) -> None:
    """Plugin entry point invoked by Hermes during plugin discovery."""
    ctx.register_platform(
        name="http_callback",
        label="HTTP Callback",
        adapter_factory=lambda cfg: HttpCallbackAdapter(cfg),
        check_fn=check_requirements,
        validate_config=validate_config,
        is_connected=is_connected,
        required_env=[],
        install_hint="aiohttp (bundled with Hermes — no extra install needed)",
        emoji="🔗",
        pii_safe=True,
        allow_update_command=False,
        platform_hint=(
            "Você está respondendo via callback HTTP a um sistema backend. "
            "Sua resposta será enviada por POST JSON a um endpoint configurado "
            "pelo desenvolvedor — não vai para um chat humano direto. Mantenha "
            "o formato natural como se fosse pro cliente final; o backend "
            "encaminha sua resposta ao destinatário real."
        ),
    )
