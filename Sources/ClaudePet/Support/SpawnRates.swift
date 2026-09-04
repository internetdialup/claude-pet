import Foundation

/// THE SPAWN MATRIX — how often anything happens, in one place.
///
/// Every visual effect in the app is gated by `noise(cycle &* A &+ B) <
/// chance` on a cycle of its own length. Before this table those thresholds
/// were magic numbers at twenty-odd call sites, tuned one at a time and
/// years apart, and only four of them were even named. The consequence was
/// not that any single rate was wrong — it was that **nobody could see the
/// rates next to each other**, so their relative frequency was emergent
/// rather than chosen, and "he should skate more" had no place to be said.
///
/// This is that place. Each entry carries the die's own two numbers and
/// reports the rate they imply, so the table can be read as taste
/// ("a skate session every quarter hour") instead of as arithmetic
/// ("0.22 over a hundred and eighty seconds").
///
/// ## What the rates were when this table was written
///
/// Per hour of unbroken idle, measured off the dice rather than guessed:
///
/// | spawn | per hour |
/// | --- | ---: |
/// | flourishes, all | 360 |
/// | — skate beats, of those | 246 |
/// | idle heart | 24 |
/// | shell glint | 24 |
/// | floor bug | 12 |
/// | stargaze (23:00–04:00 only) | 10.5 |
/// | balloon | 6 |
/// | skate session | 4.4 |
/// | sun patch (daylight only) | 2.1 |
///
/// Which is the fact worth keeping in view: **skateboarding is already most
/// of what he does.** A skate beat lands every fifteen seconds of idle, and
/// everything else in the list put together is under a tenth of that. When
/// the next request is "more skating", the honest answer is usually to raise
/// the RARE skate things — the golden board, the session, the steeze — and
/// not the base rate, which has very little room left to give.
///
/// ## The rule this table exists to keep
///
/// A threshold that is not here is a threshold nobody can find. Anything
/// gated on dice states its odds in this file and reads them from it.
enum SpawnRates {

    /// One scheduled thing: the odds it fires, and how often it asks.
    ///
    /// Both numbers travel together because neither means anything alone —
    /// a 0.22 is frequent on an eight-second cycle and rare on a three
    /// minute one, which is exactly the confusion that made the old scatter
    /// of literals impossible to compare.
    struct Spawn: Sendable {
        let chance: Double
        /// Seconds between rolls.
        let period: Double

        /// What the two numbers actually mean, for reading and for tests.
        var perHour: Double { chance * 3600 / period }
    }

    /// A costume's own effect: the same pair, plus how long it lasts once it
    /// fires. These ride `propPhase` rather than an idle clock and only roll
    /// while their costume is worn.
    struct Effect: Sendable {
        /// Its addend on the `97 &* n` costume family. Carried here rather
        /// than at the call site so one entry answers both questions a
        /// scheduled effect has — which die, and how often.
        let salt: Int
        let chance: Double
        let period: Double
        let duration: Double
    }

    // MARK: - What the wardrobe does to the odds

    /// How a worn costume bends the matrix.
    ///
    /// A costume that only changes his colours is a paint job; one that
    /// changes what he DOES is a character. The same argument that earned
    /// the per-costume shout lines earns this — and it is a table rather
    /// than a branch so the next look that wants a lean adds a row instead
    /// of a special case.
    ///
    /// The weights are additive and the rates multiplicative, deliberately:
    /// a deck entry is a count and a rate is a frequency, and mixing the two
    /// kinds of knob is how a table stops being readable.
    struct Lean: Sendable {
        /// × the skate session's rate.
        var session: Double = 1
        /// × the rare skate specials — the golden board and the steeze.
        var specials: Double = 1
        /// + on every skate trick's weight in the flourish deck.
        var trick: Int = 0
        /// + on the roll-away's.
        var cruise: Int = 0
        /// + on the still, non-skate flourishes.
        var still: Int = 0
    }

    /// **The deck is already 85% skate**, so the Skater's lean does most of
    /// its work on the session and the specials, where there is headroom,
    /// rather than on a share that cannot go much past ninety.
    ///
    /// Note what is NOT here: headwear. It draws on the bare crab only, so
    /// a costume can never lean it — leaning it would have been a number
    /// that changed nothing, which is worse than no number.
    static func lean(for costume: Costume) -> Lean {
        switch costume {
        // 🛹 Dressed to skate: the long ride comes round twice as often,
        // the jackpot and the steeze double, and the deck leans as far as a
        // deck this skate-heavy can.
        case .skater: Lean(session: 2.2, specials: 2, trick: 2, cruise: 1)
        // 💨 Speed, which in this rig is the CRUISE — the beat where he
        // holds still and the world streaks past him. Not the tricks: going
        // fast is not the same as flipping the board.
        case .sonic: Lean(session: 1.3, cruise: 4)
        // 🤖 Deliberate. A mech does not fidget, so the still moves come up
        // more and the sessions less — the one lean in the table that makes
        // him skate LESS, and it should, because that is the character.
        case .gundam: Lean(session: 0.6, still: 2)
        // Every other look is a colourway. This is where its lean goes.
        default: Lean()
        }
    }

    // MARK: - Idle spectacle
    //
    // The things he does unprompted, in descending order of how often you
    // will see them. All of these roll on the idle clock and none of them
    // fire in cycle zero — the frozen sentinel is the schedulers' job, not
    // this table's.

    /// Whether an idle cycle plays a flourish at all.
    ///
    /// Raised to 80% at the operator's call, and it is worth writing down
    /// what that spends: the quiet stretches fall from 86% of the time to
    /// about 80%, and the ruling this number carries — "he should move
    /// sometimes, and be still most of the time" — was itself the fix for a
    /// version that fired every cycle and read as a metronome. If he ever
    /// starts feeling busy rather than alive, this is the number, and it is
    /// a one-line revert.
    static let flourish = Spawn(chance: 0.80, period: 7)             // 411/hr
    /// 🛹 The long ride — several tricks strung together. The rarest thing
    /// he does on a board, and the one most worth catching.
    static let skateSession = Spawn(chance: 0.35, period: 180)       // 7/hr
    /// 💗 The idle heart.
    static let idleHeart = Spawn(chance: 0.30, period: 45)           // 24/hr
    /// ✨ A second and a half of light across the shell.
    static let shellGlint = Spawn(chance: 0.40, period: 60)          // 24/hr
    /// 🐛 The floor bug's crossing.
    static let floorBug = Spawn(chance: 0.30, period: 90)            // 12/hr
    /// 🌟 The midnight stargazer. Hour-gated to 23:00–04:00 on top of this,
    /// so the real rate is this one times however much of the night he is
    /// left running.
    static let stargaze = Spawn(chance: 0.35, period: 120)           // 10.5/hr, nights
    /// 🎈 The rare float.
    static let balloon = Spawn(chance: 0.25, period: 150)            // 6/hr
    /// ☀️ The patch of sun. Hour-gated to 08:00–17:00.
    static let sunPatch = Spawn(chance: 0.25, period: 420)           // 2.1/hr, daylight

    /// 💫 A shooting star, asked only once a stargaze is already running —
    /// so this is a share of those, not a rate of its own.
    static let shootingStarShare = 0.4

    // MARK: - The skate specials
    //
    // Asked at a skate beat, not on a clock of their own: these are the
    // "what kind of beat was that" dice, and they are where the skating
    // gets its texture. Raising these is what "more skating" almost always
    // means, because the base rate is already saturated.

    /// 🛹✨ One skate beat in twenty rides the golden board. Raised from
    /// one in fifty at the operator's call: the jackpot was so rare that
    /// most people running him had never once seen it, which makes it a
    /// feature nobody has.
    static let goldenBoard = 0.05
    /// 🧢 Nearly a beat in two comes out in headwear — the low half of the
    /// band is the beanie, the upper half the cap.
    static let headwear = 0.45
    /// 🦵 Half of his ollies are steezed, the back leg boned out.
    static let steeze = 0.50

    // MARK: - Moods with weather of their own

    /// 🔥 The cooking heat cascade.
    static let heatCascade = Spawn(chance: 0.45, period: 8)
    /// 🪩 The disco tint, while cooking.
    static let discoTint = Spawn(chance: 0.22, period: 45)
    /// The near-done glow, once a job is four fifths through.
    static let nearDoneGlow = Spawn(chance: 0.50, period: 20)
    /// The fire prop dropping to his feet instead of his crown.
    static let fireBurnsLow = Spawn(chance: 0.35, period: 45)

    // MARK: - What he says, and what he wears while saying it
    //
    // These roll on the bubble's seed rather than an idle cycle, so they
    // are shares of a showing rather than rates per hour. They live here
    // anyway: "how often does he put the shades on" is a spawn question
    // whatever domain answers it.

    /// Whether an idle beat spends itself on something he KNOWS.
    static let informationalBeat = 0.5
    /// Whether a beat the cadence silenced speaks anyway.
    static let quietBeatSpeaks = 0.6
    /// Whether an informational beat is a tip rather than a fun fact.
    static let tipOverFact = 0.34
    /// 😎 Whether a fact showing drops the deal-with-it shades…
    static let factShades = 0.5
    /// …and whether they land with a ding.
    static let shadesDing = 0.35
    /// Whether a quiet stretch produces unprompted chatter.
    static let idleChatter = 1.0 / 3.0
    /// The bubble's own shimmer.
    static let bubbleShimmer = Spawn(chance: 0.5, period: 7)

    // MARK: - Costume effects
    //
    // One per wardrobe that has something to say, all on the `97 &+ n`
    // family, all rolling on `propPhase` while their costume is worn. They
    // are listed together because that is the only way to notice that the
    // Gundam scans twice as slowly as Sonic dashes.

    /// 🎃 The pumpkin's candle flicker.
    static let pumpkinFlicker = Effect(salt: 5, chance: 0.5, period: 8, duration: 0.6)
    /// 🦃 The turkey's strut.
    static let turkeyStrut = Effect(salt: 7, chance: 0.5, period: 9, duration: 0.9)
    /// 🥷 The ninja's shuriken.
    static let shuriken = Effect(salt: 11, chance: 0.55, period: 9, duration: 2.2)
    /// ⚡ Frankenstein's bolt sparks.
    static let frankensteinSparks = Effect(salt: 13, chance: 0.5, period: 7, duration: 0.7)
    /// 🎅 The santa's cold breath.
    static let santaBreath = Effect(salt: 17, chance: 0.4, period: 10, duration: 0.8)
    /// 🤖 The Gundam's camera scan.
    static let gundamScan = Effect(salt: 19, chance: 0.35, period: 12, duration: 1.8)
    /// 🤖 …and its eye flare.
    static let gundamEyeFlare = Effect(salt: 41, chance: 0.5, period: 7, duration: 0.6)
    /// 💨 Sonic's dash.
    static let sonicDash = Effect(salt: 23, chance: 0.4, period: 9, duration: 1.6)
    /// 💍 Sonic's rings.
    static let sonicRings = Effect(salt: 29, chance: 0.4, period: 8, duration: 2.0)
    /// 🖤 Retro Black's clearcoat sheen.
    static let retroSheen = Effect(salt: 31, chance: 0.45, period: 11, duration: 1.6)
    /// 🛹 The skater's kick-push.
    static let kickPush = Effect(salt: 43, chance: 0.45, period: 9, duration: 0.8)
    /// 🎆 New Year's fireworks.
    static let fireworks = Effect(salt: 3, chance: 0.45, period: 13, duration: 1.9)
}
