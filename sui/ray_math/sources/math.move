module ray_math::math {
    const RAY: u256 = 1000000000000000000000000000;

    const HALF_RAY: u256 = 500000000000000000000000000;

    const DOUBLE_RAY: u256 = 2000000000000000000000000000;

    const LN2: u256 = 693147180559945309417232121;

    /// Error
    const ENEGATIVE_LOG: u64 = 0;

    public fun ray(): u256 {
        RAY
    }

    public fun ray_ln2(): u256 {
        LN2
    }

    public fun ray_mul(a: u256, b: u256): u256 {
        (a * b + RAY / 2) / RAY
    }

    public fun ray_div(a: u256, b: u256): u256 {
        (a * RAY + b / 2) / b
    }

    /// Return the larger of `x` and `y`
    public fun max(x: u256, y: u256): u256 {
        if (x > y) {
            x
        } else {
            y
        }
    }

    /// Return the smaller of `x` and `y`
    public fun min(x: u256, y: u256): u256 {
        if (x < y) {
            x
        } else {
            y
        }
    }

    public fun ray_log2(x: u256): u256 {
        assert!(x >= RAY, ENEGATIVE_LOG);

        // Calculate the integer part of the logarithm
        let n = log2(x / RAY);

        let result = (n as u256) * RAY;

        let y = x >> n;

        // If y is 1, the fractional part is zero
        if (y == RAY) {
            return result
        };

        // Calculate the fractional part via the iterative approximation
        let delta = HALF_RAY;
        while (delta > 0) {
            y = (y * y) / RAY;

            if (y >= DOUBLE_RAY) {
                result = result + delta;
                y = y >> 1;
            };
            delta = delta >> 1;
        };
        result
    }

    public fun log2(value: u256): u8 {
        let result = 0;
        if (value >> 128 > 0) {
            value = value >> 128;
            result = result + 128;
        };
        if (value >> 64 > 0) {
            value = value >> 64;
            result = result + 64;
        };
        if (value >> 32 > 0) {
            value = value >> 32;
            result = result + 32;
        };
        if (value >> 16 > 0) {
            value = value >> 16;
            result = result + 16;
        };
        if (value >> 8 > 0) {
            value = value >> 8;
            result = result + 8;
        };
        if (value >> 4 > 0) {
            value = value >> 4;
            result = result + 4;
        };
        if (value >> 2 > 0) {
            value = value >> 2;
            result = result + 2;
        };
        if (value >> 1 > 0) {
            result = result + 1;
        };
        result
    }
}
