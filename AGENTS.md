# Code style

- Do not write comments at all, unless it documents an unexpected API
  requirement or gotcha (e.g. a surprising API behavior or workaround).
- Never comment to explain *what* the code does, restate logic, or justify a
  design choice. No multi-line blocks, no doc comments.

# Concurrency

- Respect Swift 6 strict concurrency. Code must compile cleanly under the
  Swift 6 language mode without data-race or actor-isolation errors.
- In an `actor`'s `init`, only assign to stored properties; never read an
  isolated property back (e.g. `self.foo`) before init completes, or the
  compiler treats `self` as fully initialized and rejects later assignments.
  Use a local variable and assign once.
- Keep `Sendable` correct: don't capture non-`Sendable` values across
  isolation boundaries, and prefer marking types `Sendable` over reaching for
  `@unchecked Sendable` or `nonisolated(unsafe)`.

# Commits

- Always commit changes once they are made; don't leave work uncommitted.
- Commit directly to the `main` branch unless told otherwise; don't create
  feature branches on your own.
- Keep each commit focused on one logical change. For large changes, split
  the work into multiple commits so each significant change (e.g. a refactor,
  a new feature, a migration, a UI change) is in its own commit, rather than
  one commit for everything.
- Write commit messages as a short imperative summary of the change (e.g.
  "Rename More sheet to Settings").
