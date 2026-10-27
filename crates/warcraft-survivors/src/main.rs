//! The `warcraft-survivors` launcher: the build stamp, handed to the survivors mode.

use benilla_app::BuildId;

fn main() -> benilla_app::AppExit {
    // A double-clicked .app must not look for game data or write settings inside its own
    // bundle; a terminal run is not a bundle and this does nothing. See `bundle`. The bin
    // links this package's lib automatically; it does not redeclare the module.
    warcraft_survivors::bundle::prepare();
    benilla_app::run_survivors(BuildId {
        version: env!("CARGO_PKG_VERSION"),
        describe: env!("BENILLA_GIT_DESCRIBE"),
        sha: env!("BENILLA_GIT_SHA"),
        short: env!("BENILLA_GIT_SHORT"),
        date: env!("BENILLA_GIT_DATE"),
        profile: env!("BENILLA_PROFILE"),
        project_dir: env!("BENILLA_PROJECT_DIR"),
        ..Default::default()
    })
}
