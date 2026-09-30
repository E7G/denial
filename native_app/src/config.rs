use std::{env, path::PathBuf, sync::Arc};

use denial_flutter_engine::{DartRuntimeMode, EngineLibrary, EngineProject, RendererBackend};

pub const HELP: &str = "denial-app --bundle DIR --engine FILE [--app-id ID] [--title TITLE]
           [--width PIXELS] [--height PIXELS] [--renderer impeller|skia] [--check]

Runs one existing release Flutter AOT bundle as a native Wayland application.
--engine defaults to $DENIAL_FLUTTER_BUNDLE/lib/libflutter_engine.so.
--check validates the bundle and raw engine ABI without opening a window.
Dart entrypoint arguments and GTK platform plugins are not supported yet.";

pub struct Config {
    pub project: EngineProject,
    pub app_id: String,
    pub title: String,
    pub width: u32,
    pub height: u32,
    pub check: bool,
}

impl Config {
    pub fn parse() -> Result<Option<Self>, String> {
        let mut bundle = None;
        let mut engine = env::var_os("DENIAL_FLUTTER_BUNDLE")
            .map(|p| PathBuf::from(p).join("lib/libflutter_engine.so"));
        let mut app_id = "org.denial.NativeApp".to_owned();
        let mut title = "Denial app".to_owned();
        let (mut width, mut height) = (1000, 700);
        let mut renderer = RendererBackend::ImpellerGles;
        let mut check = false;
        let mut args = env::args_os().skip(1);
        while let Some(arg) = args.next() {
            let arg = arg.to_str().ok_or("option is not UTF-8")?;
            if matches!(arg, "--help" | "-h") {
                return Ok(None);
            }
            if arg == "--check" {
                check = true;
                continue;
            }
            if !matches!(
                arg,
                "--bundle"
                    | "--engine"
                    | "--app-id"
                    | "--title"
                    | "--width"
                    | "--height"
                    | "--renderer"
            ) {
                return Err(format!("unknown option: {arg}"));
            }
            let value = args
                .next()
                .ok_or_else(|| format!("missing value for {arg}"))?;
            match arg {
                "--bundle" => bundle = Some(PathBuf::from(value)),
                "--engine" => engine = Some(PathBuf::from(value)),
                "--app-id" => app_id = value.into_string().map_err(|_| "app ID is not UTF-8")?,
                "--title" => title = value.into_string().map_err(|_| "title is not UTF-8")?,
                "--width" | "--height" => {
                    let n = value
                        .to_str()
                        .and_then(|s| s.parse::<u32>().ok())
                        .filter(|n| (1..=16_384).contains(n))
                        .ok_or("window dimensions must be between 1 and 16384")?;
                    if arg == "--width" {
                        width = n;
                    } else {
                        height = n;
                    }
                }
                "--renderer" => {
                    renderer = value
                        .to_str()
                        .ok_or("renderer is not UTF-8")?
                        .parse()
                        .map_err(|e: denial_flutter_engine::ParseRendererBackendError| {
                            e.to_string()
                        })?
                }
                _ => unreachable!(),
            }
        }
        let bundle = bundle
            .ok_or("--bundle is required")?
            .canonicalize()
            .map_err(|e| e.to_string())?;
        let engine_library = engine
            .ok_or("--engine or DENIAL_FLUTTER_BUNDLE is required")?
            .canonicalize()
            .map_err(|e| e.to_string())?;
        let project = EngineProject {
            engine_library,
            assets: bundle.join("data/flutter_assets"),
            icu_data: bundle.join("data/icudtl.dat"),
            runtime: DartRuntimeMode::Aot,
            aot_library: Some(bundle.join("lib/libapp.so")),
            renderer_backend: renderer,
            resource_cache_max_bytes_threshold: 64 * 1024 * 1024,
        };
        for path in [
            &project.assets,
            &project.icu_data,
            project.aot_library.as_ref().unwrap(),
        ] {
            if !path.exists() {
                return Err(format!("missing bundle component: {}", path.display()));
            }
        }
        Ok(Some(Self {
            project,
            app_id,
            title,
            width,
            height,
            check,
        }))
    }

    pub fn check(&self) -> Result<(), Box<dyn std::error::Error>> {
        // Loading checks the raw embedder proc table and Denial extension ABI.
        // It starts no engine, connects to no display and creates no UI state.
        let library = Arc::new(EngineLibrary::load(&self.project.engine_library)?);
        if !library.runs_aot_compiled_dart_code() {
            return Err("a release AOT engine is required".into());
        }
        let _aot = library.create_aot_data(self.project.aot_library.as_ref().unwrap())?;
        println!(
            "Bundle, AOT image and raw engine ABI OK: {}",
            self.project.assets.display()
        );
        Ok(())
    }
}
