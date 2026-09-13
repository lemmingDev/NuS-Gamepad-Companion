/// Connection lifecycle exposed to the UI.
///
/// Mirrors the lifecycle previously defined in `NusClient` so existing
/// consumers can migrate without behavioural change.
enum NusConnState { idle, scanning, connecting, ready, error }
