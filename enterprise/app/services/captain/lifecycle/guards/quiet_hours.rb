# frozen_string_literal: true

class Captain::Lifecycle::Guards::QuietHours < Captain::Lifecycle::Guards::Base
  MAX_DELAY = 2.hours

  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    return pass unless config.quiet_hours_enabled
    return pass unless in_quiet_window?(@delivery.fire_at, config)

    delayed_to = next_valid_time(@delivery.fire_at, config)
    delay = delayed_to - @delivery.fire_at
    return skip('too_stale') if delay > MAX_DELAY

    reschedule(delayed_to)
  end

  private

  def in_quiet_window?(time, config)
    from_min = to_minutes(config.quiet_hours_from)
    to_min   = to_minutes(config.quiet_hours_to)
    cur_min  = (time.hour * 60) + time.min

    if from_min < to_min
      # Same-day window (e.g. 14:00–18:00)
      cur_min >= from_min && cur_min < to_min
    else
      # Crosses midnight (e.g. 23:00–08:00)
      cur_min >= from_min || cur_min < to_min
    end
  end

  def next_valid_time(fire_at, config)
    to_min   = to_minutes(config.quiet_hours_to)
    from_min = to_minutes(config.quiet_hours_from)
    fire_min = (fire_at.hour * 60) + fire_at.min

    # Base target: today at quiet_hours_to
    target = fire_at.beginning_of_day + to_min.minutes

    # If window crosses midnight AND fire_at is in the evening half (>= from),
    # the window end ("to") is tomorrow morning.
    target += 1.day if from_min > to_min && fire_min >= from_min

    target
  end

  def to_minutes(time_value)
    (time_value.hour * 60) + time_value.min
  end
end
