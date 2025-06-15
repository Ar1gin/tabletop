const TimeType = u64;
const TIME_UNIT: TimeType = 1 << 32;
const TIME_MULT = 1.0 / @as(f32, @floatFromInt(TIME_UNIT));
const Time = @This();

pub const ZERO = Time{ .clock = 0 };

clock: TimeType,

pub fn tick(self: *Time, units: f32) void {
    self.clock += durationFromUnits(units);
}

pub fn past(self: *Time, goal: Time) bool {
    return self.clock >= goal.clock;
}

pub fn offset(self: Time, units: f32) Time {
    return Time{
        .clock = self.clock + durationFromUnits(units),
    };
}

pub fn unitsSince(self: *Time, from: Time) f32 {
    if (from.clock > self.clock) return 0;
    return @as(f32, @floatFromInt(self.clock - from.clock)) * TIME_MULT;
}

pub fn progress(self: *Time, from: Time, to: Time) f32 {
    if (from.clock > to.clock) return 1.0;
    if (self.clock > to.clock) return 1.0;

    const duration = to.clock - from.clock;
    return @as(f32, @floatFromInt(self.clock - from.clock)) / @as(f32, @floatFromInt(duration));
}

pub fn unitsFromDuration(duration: TimeType) f32 {
    return @as(f32, @floatFromInt(duration)) * TIME_MULT;
}

pub fn durationFromUnits(units: f32) TimeType {
    return @intFromFloat(@as(f32, @floatFromInt(TIME_UNIT)) * units);
}
