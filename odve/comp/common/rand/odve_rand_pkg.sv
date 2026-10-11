// odve_rand_pkg - random numbers that are the same on every simulator.
//
// The same +SEED gives the same values on Verilator and Questa/ModelSim, run
// after run. $urandom, $random and randomize() cannot do that: their
// generators are vendor-specific (Verilator uses xoroshiro128** for all of
// them). $dist_uniform is the one generator the standard defines bit for bit
// (IEEE 1800 Annex N), and every value here comes from it. See README for the
// rules behind the code and the measurements.
//
//     import odve_rand_pkg::*;
//     odve_rand rng = new(get_full_name());     // a stream of its own, seeded from +SEED
//     len   = rng.urange(15);                   // like $urandom_range(15, 0)
//     n     = rng.urand(1, 16);                 // [lo:hi]
//     addr  = rng.urand64(base, base + size - 1); // 64-bit [lo:hi]
//     if (rng.chance(30)) ...                   // 1 with 30% probability
//     kind  = rng.weighted('{70, 20, 10});      // index 0, 1 or 2 by weight
//     item  = q[rng.index(q.size())];           // any element of a queue
//     child = rng.spawn("item");                // a new stream drawn from this one
//
// Each odve_rand is one stream: the seed of its own, derived from the run
// seed (+SEED=<n>) and the stream name. Give every component (driver,
// monitor, sequence) its own stream, so a draw added in one place does not
// shift the values everywhere else, and so threads never share one.
package odve_rand_pkg;

    // murmur3's 32-bit finalizer: a bijection that spreads every input bit
    // over the whole word. Close seeds (SEED, SEED+1) give unrelated streams.
    function automatic int unsigned odve_rand_mix(int unsigned h);
        h ^= h >> 16;
        h *= 32'h85EB_CA6B;
        h ^= h >> 13;
        h *= 32'hC2B2_AE35;
        h ^= h >> 16;
        return h;
    endfunction

    // FNV-1a over the bytes of a string
    function automatic int unsigned odve_rand_hash(string s);
        int unsigned h = 32'h811C_9DC5;
        for (int i = 0; i < s.len(); i++) begin
            h ^= {24'h0, s[i]};
            h *= 32'h0100_0193;
        end
        return h;
    endfunction

    class odve_rand;
        local static bit          m_run_seed_set;
        local static int unsigned m_run_seed;

        local string m_name;
        local int    m_state;   // the $dist_uniform seed variable

        // A stream named `name`, seeded from the run seed and the name.
        function new(string name = "odve_rand");
            m_name = name;
            set_seed(stream_seed(name));
        endfunction

        // ---- seeds

        // The run seed: +SEED=<n> (odve's run.mk passes the make SEED), or 1
        // without one.
        static function int unsigned run_seed();
            if (!m_run_seed_set) begin
                if (!$value$plusargs("SEED=%d", m_run_seed)) begin
                    m_run_seed = 1;
                    $display("odve_rand: no +SEED=<n> on the command line, using SEED=1");
                end
                m_run_seed_set = 1;
            end
            return m_run_seed;
        endfunction

        // Overrides +SEED for every stream created after the call.
        static function void set_run_seed(int unsigned seed);
            m_run_seed     = seed;
            m_run_seed_set = 1;
        endfunction

        // The seed of the stream called `name` in this run.
        static function int unsigned stream_seed(string name);
            return odve_rand_mix(run_seed() ^ odve_rand_mix(odve_rand_hash(name)));
        endfunction

        // The stream's state: get_seed() now and set_seed() later replays
        // every value drawn in between.
        function int unsigned get_seed();
            return m_state;
        endfunction

        function void set_seed(int unsigned seed);
            m_state = int'(seed);
        endfunction

        function string get_name();
            return m_name;
        endfunction

        // A new stream for an object made over and over (a sequence item, a
        // sub-sequence): its seed is a value drawn from this stream, mixed
        // with the name. Streams named only by `new(name)` would repeat for
        // objects that share a name.
        function odve_rand spawn(string name = "");
            odve_rand    r = new(name);
            int unsigned x = u32();
            r.set_seed(odve_rand_mix(x ^ odve_rand_hash(name)));
            return r;
        endfunction

        // ---- draws

        // 16 random bits: the only $dist_uniform call. A range of a power of
        // two is computed exactly in floating point on any simulator (Annex N
        // scales a 23-bit fraction), where other ranges can round differently.
        // Wider values and other ranges are built from these by integer
        // arithmetic below. The call must stay inside a function: Verilator
        // takes a bare $dist_uniform for a pure function, so in a `case`
        // selector or a ?: it can be evaluated more or less than once.
        function int unsigned u16();
            return $dist_uniform(m_state, 0, 65535);
        endfunction

        // Statement by statement: the operands of one expression may be
        // evaluated in any order, so two draws never share one.
        function int unsigned u32();
            int unsigned x = u16();
            x = (x << 16) | u16();
            return x;
        endfunction

        function longint unsigned u64();
            longint unsigned x = 64'(u32());
            x = (x << 32) | 64'(u32());
            return x;
        endfunction

        // [0:n-1], each value equally likely; n == 0 means all 2^64 values.
        // A draw from the incomplete top block of the word is drawn again
        // (Lemire's threshold, 2^w mod n), so small ranges carry no bias.
        function longint unsigned below(longint unsigned n);
            longint unsigned x, t;
            if (n == 0) return u64();
            if (n == 1) return 0;
            if (n <= 64'h1_0000) begin
                t = (64'h1_0000 - n) % n;
                x = 64'(u16());
                while (x < t) x = 64'(u16());
            end else if (n <= 64'h1_0000_0000) begin
                t = (64'h1_0000_0000 - n) % n;
                x = 64'(u32());
                while (x < t) x = 64'(u32());
            end else begin
                t = (64'd0 - n) % n;
                x = u64();
                while (x < t) x = u64();
            end
            return x % n;
        endfunction

        // [lo:hi] inclusive; an empty range (hi < lo) gives lo.
        function int unsigned urand(int unsigned lo, int unsigned hi);
            if (hi <= lo) return lo;
            return lo + 32'(below(64'(hi - lo) + 1));
        endfunction

        // [lo:hi] inclusive, 64-bit; an empty range (hi < lo) gives lo.
        function longint unsigned urand64(longint unsigned lo, longint unsigned hi);
            if (hi <= lo) return lo;
            return lo + below(hi - lo + 1);
        endfunction

        // [min:max] like $urandom_range(max, min): the bounds in either order.
        function int unsigned urange(int unsigned max, int unsigned min = 0);
            return (max < min) ? urand(max, min) : urand(min, max);
        endfunction

        // [lo:hi] inclusive, signed; an empty range (hi < lo) gives lo.
        function int irand(int lo, int hi);
            if (hi <= lo) return lo;
            return int'(longint'(lo) + longint'(below(64'(longint'(hi) - longint'(lo) + 1))));
        endfunction

        // 1 with a probability of pct percent (0: never, >= 100: always).
        function bit chance(int unsigned pct);
            if (pct == 0)   return 1'b0;
            if (pct >= 100) return 1'b1;
            return below(100) < 64'(pct);
        endfunction

        // An index into an array of n elements, [0:n-1] (0 for n == 0).
        function int unsigned index(int unsigned n);
            if (n <= 1) return 0;
            return 32'(below(n));
        endfunction

        // An index into w, chosen with probability w[i] / sum(w): the `dist`
        // of a constraint. All weights 0 (or no weights) gives 0.
        function int unsigned weighted(int unsigned w[]);
            longint unsigned sum = 0, x;
            foreach (w[i]) sum += 64'(w[i]);
            if (sum == 0) return 0;
            x = below(sum);
            foreach (w[i]) begin
                if (x < 64'(w[i])) return i;
                x -= 64'(w[i]);
            end
            return 0;   // not reached
        endfunction
    endclass

endpackage
