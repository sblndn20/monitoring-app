-- Buffer states.
--
-- These are plain strings on purpose. NIDAS used table identities ({name="ON"})
-- and compared them with ==, which silently breaks the moment a state crosses
-- serialization (saved to disk, sent over a modem) and comes back as a
-- different table. Strings survive that round trip.

return {
    ONLINE  = "ONLINE",   -- accepting or supplying power
    IDLE    = "IDLE",     -- powered, nothing flowing
    OFF     = "OFF",      -- work disabled (soft-mallet / redstone)
    PROBLEM = "PROBLEM",  -- maintenance required
    MISSING = "MISSING",  -- component not reachable
}
