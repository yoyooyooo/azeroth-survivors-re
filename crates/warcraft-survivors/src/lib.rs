//! The `warcraft-survivors` launcher's own logic, as a library so it can be tested: a `[[bin]]`
//! with `test = false` (the shim must not relink the app on every commit) has no test target of
//! its own. Today that is [`bundle`], the paths a macOS `.app` has to answer for itself.
//!
//! `main.rs` calls [`bundle::prepare`] through this lib. Cargo links a package's lib into its
//! bin on its own, so the bin does not declare the module a second time.

pub mod bundle;
