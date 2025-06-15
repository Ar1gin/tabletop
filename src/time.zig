const TimeType = u64;
const TIME_UNIT: TimeType = 1 << 32;
const TIME_MULT = 1.0 / @as(f32, @floatFromInt(TIME_UNIT));

clock: TimeType,

const Time = @This();

pub fn tick(self: *Time, units: f32) void {
    self.clock += durationFromUnits(units);
}

pub fn unitsSince(self: *Time, from: Time) f32 {
    if (from.clock > self.clock) return 0;
    return @as(f32, @floatFromInt(self.clock - from.clock)) * TIME_MULT;
}

pub fn durationFromUnits(units: f32) TimeType {
    return @intFromFloat(@as(f32, @floatFromInt(TIME_UNIT)) * units);
}
