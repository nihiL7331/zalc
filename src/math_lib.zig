const std = @import("std");

pub fn sin(x: f64) f64 {
    return std.math.sin(x);
}

pub fn cos(x: f64) f64 {
    return std.math.cos(x);
}

pub fn tan(x: f64) f64 {
    return std.math.tan(x);
}

pub fn asin(x: f64) f64 {
    return std.math.asin(x);
}

pub fn acos(x: f64) f64 {
    return std.math.acos(x);
}

pub fn atan(x: f64) f64 {
    return std.math.atan(x);
}

pub fn sqrt(x: f64) f64 {
    return std.math.sqrt(x);
}

pub fn cbrt(x: f64) f64 {
    return std.math.cbrt(x);
}

pub fn pow(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

pub fn log(x: f64) f64 {
    return std.math.log10(x);
}

pub fn ln(x: f64) f64 {
    return std.math.log(f64, std.math.e, x);
}

pub fn ceil(x: f64) f64 {
    return std.math.ceil(x);
}

pub fn floor(x: f64) f64 {
    return std.math.floor(x);
}

pub fn round(x: f64) f64 {
    return std.math.round(x);
}

pub fn abs(x: f64) f64 {
    return @abs(x);
}

pub fn min(a: f64, b: f64) f64 {
    return if (a < b) a else b;
}

pub fn max(a: f64, b: f64) f64 {
    return if (a > b) a else b;
}

pub fn gcd(a: i64, b: i64) i64 {
    if (b == 0) return a;
    return gcd(b, @mod(a, b));
}

pub fn lcm(a: i64, b: i64) i64 {
    return (a / gcd(a, b)) * b;
}

pub fn degrees(rad: f64) f64 {
    return rad * 180.0 / std.math.pi;
}

pub fn radians(deg: f64) f64 {
    return deg * std.math.pi / 180.0;
}
