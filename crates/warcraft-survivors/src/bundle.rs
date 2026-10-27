//! The two paths a macOS `.app` has to answer for itself, answered through the environment
//! variables the client's own resolvers already read first — `$WOW_DATA`
//! (`benilla_formats::wow_data`) and `$BENILLA_HOME` (`benilla_app::local_state`) — so no client
//! code learns about bundles.
//!
//! Both of the client's defaults are wrong inside one. The install is looked for beside the
//! executable, `Azeroth Survivors.app/Contents/MacOS/Data`, which is *inside* the code signature:
//! a player who put game data there would break it, and macOS then refuses to open the app at
//! all. The state folder is `benilla-config/` in that same place, which the client writes on its
//! first settings change. A `.dmg` also mounts read-only, so a bundle that tried to write at all
//! would fail there.
//!
//! So a bundled run keeps both outside the app, in `~/Library/Application Support/Azeroth
//! Survivors/` — with the game data in its `Data/`, or in a `Data/` (or `WoW/Data/`) folder beside
//! the `.app` for a portable copy. Nothing here fires unless the executable sits at
//! `<something>.app/Contents/MacOS/`; a terminal run, a dev build and every non-macOS target are
//! untouched, and an explicit `$WOW_DATA`/`$BENILLA_HOME` always wins.

use std::path::{Path, PathBuf};

/// The folder under `~/Library/Application Support` that holds a bundled player's game data and
/// settings: the app's own name, so a player looking for it finds it.
const SUPPORT: &str = "Azeroth Survivors";

/// Point the client's resolvers at the bundle's folders, when this is a bundled run. Called once,
/// first thing in `main`, before anything resolves the install or the state folder.
pub fn prepare() {
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let Some(bundle) = bundle_root(&exe) else {
        return;
    };
    let Some(home) = std::env::var_os("HOME").filter(|h| !h.is_empty()) else {
        return;
    };
    let support = Path::new(&home)
        .join("Library/Application Support")
        .join(SUPPORT);

    if std::env::var_os("BENILLA_HOME").is_none() {
        std::env::set_var("BENILLA_HOME", &support);
    }
    // An explicit `$WOW_DATA` is the player's own answer: never second-guessed, and never the
    // reason to stop. Without one, the bundle's folder is the answer — set even when it does not
    // exist yet, so the client's "no WoW install found" line names the path to fill in rather
    // than one inside the bundle.
    if std::env::var_os("WOW_DATA").is_some() {
        return;
    }
    let data = data_dir(&bundle, &support);
    std::env::set_var("WOW_DATA", &data);
    if !data.is_dir() {
        no_install(&support, &data);
    }
}

/// A bundled run with no game data: a double-clicked `.app` has no terminal, so the client's own
/// "no WoW install found" line would go nowhere and the player would get a black window. Say what
/// to do, open the folder the files go into, and stop — the game cannot draw without them.
fn no_install(support: &Path, data: &Path) {
    let _ = std::fs::create_dir_all(support);
    eprintln!(
        "{SUPPORT} needs a World of Warcraft 1.12.1 (build 5875) client's Data folder.\n\
         Put its *.MPQ files in:\n  {}\n\
         then launch it again. Settings and screenshots stay in {}.",
        data.display(),
        support.display()
    );
    // Best effort, never waited on: a player who dismisses the alert still finds the folder open.
    let _ = std::process::Command::new("open").arg(support).spawn();
    let message = format!(
        "{SUPPORT} needs game data.\n\n\
         Put a World of Warcraft 1.12.1 client's *.MPQ files in:\n\n{}\n\n\
         The folder is open in the Finder. Launch the app again afterwards.",
        data.display()
    );
    let script = "on run argv\ndisplay alert \"Azeroth Survivors\" message (item 1 of argv) as critical\nend run";
    let _ = std::process::Command::new("osascript")
        .arg("-e")
        .arg(script)
        .arg(&message)
        .status();
    std::process::exit(1);
}

/// The `.app` the executable is in, or `None` when it is not in one: `<bundle>.app/Contents/MacOS/<bin>`
/// is the only layout a bundle has.
fn bundle_root(exe: &Path) -> Option<PathBuf> {
    let macos = exe.parent()?;
    let contents = macos.parent()?;
    let bundle = contents.parent()?;
    let layout = macos.file_name()? == "MacOS" && contents.file_name()? == "Contents";
    let named = bundle
        .extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("app"));
    if layout && named {
        Some(bundle.to_path_buf())
    } else {
        None
    }
}

/// Where a bundled run reads game data: a `Data/` or `WoW/Data/` folder beside the `.app` when the
/// player keeps a portable copy, else the one under Application Support (which may not exist yet).
fn data_dir(bundle: &Path, support: &Path) -> PathBuf {
    let beside = bundle.parent().unwrap_or(bundle);
    [beside.join("Data"), beside.join("WoW/Data")]
        .into_iter()
        .find(|dir| dir.is_dir())
        .unwrap_or_else(|| support.join("Data"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("survivors-bundle-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_bundle_is_recognized_only_from_contents_macos() {
        assert_eq!(
            bundle_root(Path::new(
                "/Applications/Azeroth Survivors.app/Contents/MacOS/azeroth-survivors"
            )),
            Some(PathBuf::from("/Applications/Azeroth Survivors.app"))
        );
        // A plain player build, a dev build and a renamed folder are not bundles.
        for not_a_bundle in [
            "/opt/game/azeroth-survivors",
            "/repo/target/release/warcraft-survivors",
            "/Applications/Azeroth Survivors.app/bin/azeroth-survivors",
            "/Applications/Azeroth Survivors/Contents/MacOS/azeroth-survivors",
        ] {
            assert_eq!(bundle_root(Path::new(not_a_bundle)), None, "{not_a_bundle}");
        }
    }

    #[test]
    fn data_beside_the_app_wins_over_application_support() {
        let root = tmp("beside");
        let bundle = root.join("Azeroth Survivors.app");
        std::fs::create_dir_all(bundle.join("Contents/MacOS")).unwrap();
        let support = root.join("support");

        // Nothing beside the app: the Application Support folder, which may not exist yet.
        assert_eq!(data_dir(&bundle, &support), support.join("Data"));

        std::fs::create_dir_all(root.join("WoW/Data")).unwrap();
        assert_eq!(data_dir(&bundle, &support), root.join("WoW/Data"));

        std::fs::create_dir_all(root.join("Data")).unwrap();
        assert_eq!(data_dir(&bundle, &support), root.join("Data"));
    }
}
