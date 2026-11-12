//! The power state as plain values (what the contract tells), and the rules about them that do not
//! depend on a source: UPower's numbers, the brightness arithmetic. Only data: how it looks (icons,
//! wording) is the shells' and the apps'.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DeviceKind {
    Battery,
    Ups,
    Mouse,
    Keyboard,
    Touchpad,
    GamingInput,
    Pen,
    Headset,
    Headphones,
    Speakers,
    Phone,
    Tablet,
    MediaPlayer,
    Computer,
    Wearable,
    Other,
}

impl DeviceKind {
    /// UPower's Device.Type; None for what is not a battery (line power, monitors)
    pub fn from_upower(kind: u32) -> Option<DeviceKind> {
        Some(match kind {
            1 => return None, // line power: the charger, not a battery
            2 => DeviceKind::Battery,
            3 => DeviceKind::Ups,
            4 => return None, // a monitor
            5 => DeviceKind::Mouse,
            6 => DeviceKind::Keyboard,
            8 => DeviceKind::Phone,
            9 => DeviceKind::MediaPlayer,
            10 => DeviceKind::Tablet,
            11 => DeviceKind::Computer,
            12 => DeviceKind::GamingInput,
            13 => DeviceKind::Pen,
            14 => DeviceKind::Touchpad,
            17 => DeviceKind::Headset,
            18 => DeviceKind::Speakers,
            19 => DeviceKind::Headphones,
            26 => DeviceKind::Wearable,
            _ => DeviceKind::Other,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BatteryState {
    Unknown,
    Charging,
    Discharging,
    Empty,
    Full,
    PendingCharge,
    PendingDischarge,
}

impl BatteryState {
    /// UPower's Device.State
    pub fn from_upower(state: u32) -> BatteryState {
        match state {
            1 => BatteryState::Charging,
            2 => BatteryState::Discharging,
            3 => BatteryState::Empty,
            4 => BatteryState::Full,
            5 => BatteryState::PendingCharge,
            6 => BatteryState::PendingDischarge,
            _ => BatteryState::Unknown,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum WarningLevel {
    None,
    Low,
    Critical,
    Action,
}

impl WarningLevel {
    /// UPower's Device.WarningLevel (2, "discharging", is a UPS on battery: not a warning by itself)
    pub fn from_upower(level: u32) -> WarningLevel {
        match level {
            3 => WarningLevel::Low,
            4 => WarningLevel::Critical,
            5 => WarningLevel::Action,
            _ => WarningLevel::None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Battery {
    pub id: String,
    pub kind: DeviceKind,
    pub vendor: String,
    pub model: String,
    pub present: bool,
    pub power_supply: bool,
    pub percentage: f64,
    pub state: BatteryState,
    pub warning_level: WarningLevel,
    pub time_to_empty: i64,
    pub time_to_full: i64,
    pub energy_rate: f64,
    pub capacity: f64,
}

impl Battery {
    /// No battery: the summary of a computer without one
    pub fn absent(id: &str) -> Battery {
        Battery {
            id: id.to_string(),
            kind: DeviceKind::Battery,
            vendor: String::new(),
            model: String::new(),
            present: false,
            power_supply: true,
            percentage: 0.0,
            state: BatteryState::Unknown,
            warning_level: WarningLevel::None,
            time_to_empty: 0,
            time_to_full: 0,
            energy_rate: 0.0,
            capacity: 0.0,
        }
    }

    pub fn charging(&self) -> bool {
        matches!(self.state, BatteryState::Charging | BatteryState::PendingCharge)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct PowerStatus {
    pub upower_available: bool,
    pub on_battery: bool,
    pub lid_present: bool,
    pub lid_closed: bool,
    pub summary: Battery,
}

impl PowerStatus {
    pub fn unavailable() -> PowerStatus {
        PowerStatus {
            upower_available: false,
            on_battery: false,
            lid_present: false,
            lid_closed: false,
            summary: Battery::absent("DisplayDevice"),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DisplayKind {
    BuiltIn,
    External,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Display {
    pub id: String,
    pub kind: DisplayKind,
    pub device: String,
    pub raw: u32,
    pub raw_max: u32,
}

/// The fraction of the brightness that is one step of the keys (5 %)
pub const STEP: f64 = 0.05;

impl Display {
    pub fn fraction(&self) -> f64 {
        if self.raw_max == 0 { 0.0 } else { self.raw as f64 / self.raw_max as f64 }
    }

    /// The lowest raw value setBrightness gives: one step of the hardware, so the panel stays lit
    pub fn raw_minimum(&self) -> u32 {
        if self.raw_max == 0 { 0 } else { 1 }
    }

    pub fn minimum(&self) -> f64 {
        if self.raw_max == 0 { 0.0 } else { self.raw_minimum() as f64 / self.raw_max as f64 }
    }

    /// The raw value for a fraction, rounded, never below the minimum
    pub fn raw_for(&self, fraction: f64) -> u32 {
        let raw = (fraction.clamp(0.0, 1.0) * self.raw_max as f64).round() as u32;
        raw.clamp(self.raw_minimum(), self.raw_max)
    }

    /// The raw value `steps` key presses away from `from` (5 % each); always moves by at least one
    /// raw step when it can, so that a panel with few steps still reacts
    pub fn raw_after_steps(&self, from: u32, steps: i32) -> u32 {
        if steps == 0 || self.raw_max == 0 {
            return from;
        }
        let step = ((self.raw_max as f64 * STEP).round() as i64).max(1);
        let target = from as i64 + step * steps as i64;
        (target.clamp(self.raw_minimum() as i64, self.raw_max as i64)) as u32
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct KeyboardBacklight {
    pub available: bool,
    pub raw: u32,
    pub raw_max: u32,
}

impl KeyboardBacklight {
    pub fn unavailable() -> KeyboardBacklight {
        KeyboardBacklight { available: false, raw: 0, raw_max: 0 }
    }

    pub fn fraction(&self) -> f64 {
        if self.raw_max == 0 { 0.0 } else { self.raw as f64 / self.raw_max as f64 }
    }

    /// Keyboards have few levels (often 0, 1, 2): the nearest one, and 0 is allowed (off)
    pub fn raw_for(&self, fraction: f64) -> u32 {
        (fraction.clamp(0.0, 1.0) * self.raw_max as f64).round() as u32
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Profile {
    PowerSaver,
    Balanced,
    Performance,
}

impl Profile {
    /// power-profiles-daemon's names
    pub fn from_ppd(name: &str) -> Option<Profile> {
        match name {
            "power-saver" => Some(Profile::PowerSaver),
            "balanced" => Some(Profile::Balanced),
            "performance" => Some(Profile::Performance),
            _ => None,
        }
    }

    pub fn ppd_name(&self) -> &'static str {
        match self {
            Profile::PowerSaver => "power-saver",
            Profile::Balanced => "balanced",
            Profile::Performance => "performance",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Degradation {
    None,
    LapDetected,
    HighOperatingTemperature,
    Other,
}

impl Degradation {
    /// power-profiles-daemon's PerformanceDegraded ("" when not)
    pub fn from_ppd(reason: &str) -> Degradation {
        match reason {
            "" => Degradation::None,
            "lap-detected" => Degradation::LapDetected,
            "high-operating-temperature" => Degradation::HighOperatingTemperature,
            _ => Degradation::Other,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct HeldProfile {
    pub profile: Profile,
    pub reason: String,
    pub application_id: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Profiles {
    pub available: bool,
    pub active: Profile,
    pub offered: Vec<Profile>,
    pub degraded: Degradation,
    pub holds: Vec<HeldProfile>,
}

impl Profiles {
    pub fn unavailable() -> Profiles {
        Profiles { available: false, active: Profile::Balanced, offered: Vec::new(), degraded: Degradation::None, holds: Vec::new() }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EventKind {
    ChargerConnected,
    ChargerDisconnected,
    BatteryLow,
    BatteryCritical,
    BatteryAction,
    BatteryFull,
    DeviceBatteryLow,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Event {
    pub kind: EventKind,
    pub battery_id: String,
    pub percentage: f64,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn panel(raw: u32, raw_max: u32) -> Display {
        Display { id: "backlight:x".into(), kind: DisplayKind::BuiltIn, device: "x".into(), raw, raw_max }
    }

    #[test]
    fn upower_numbers() {
        assert_eq!(DeviceKind::from_upower(1), None);
        assert_eq!(DeviceKind::from_upower(2), Some(DeviceKind::Battery));
        assert_eq!(DeviceKind::from_upower(5), Some(DeviceKind::Mouse));
        assert_eq!(DeviceKind::from_upower(19), Some(DeviceKind::Headphones));
        assert_eq!(DeviceKind::from_upower(99), Some(DeviceKind::Other));
        assert_eq!(BatteryState::from_upower(1), BatteryState::Charging);
        assert_eq!(BatteryState::from_upower(4), BatteryState::Full);
        assert_eq!(BatteryState::from_upower(0), BatteryState::Unknown);
        assert_eq!(WarningLevel::from_upower(2), WarningLevel::None);
        assert_eq!(WarningLevel::from_upower(3), WarningLevel::Low);
        assert_eq!(WarningLevel::from_upower(5), WarningLevel::Action);
    }

    #[test]
    fn brightness_never_turns_the_panel_off() {
        let p = panel(86400, 96000);
        assert!((p.fraction() - 0.9).abs() < 1e-9);
        assert_eq!(p.raw_for(0.0), 1);
        assert_eq!(p.raw_for(1.5), 96000);
        assert_eq!(p.raw_for(0.5), 48000);
        assert!(p.minimum() > 0.0 && p.minimum() < 0.001);
    }

    #[test]
    fn steps_are_five_percent_and_at_least_one() {
        let p = panel(48000, 96000);
        assert_eq!(p.raw_after_steps(48000, 1), 52800);
        assert_eq!(p.raw_after_steps(48000, -2), 38400);
        assert_eq!(p.raw_after_steps(2000, -1), 1);
        assert_eq!(p.raw_after_steps(95000, 3), 96000);
        // A panel with 7 levels still moves on every press
        let few = panel(3, 7);
        assert_eq!(few.raw_after_steps(3, 1), 4);
        assert_eq!(few.raw_after_steps(1, -1), 1);
    }

    #[test]
    fn keyboards_may_be_off() {
        let k = KeyboardBacklight { available: true, raw: 1, raw_max: 2 };
        assert_eq!(k.raw_for(0.0), 0);
        assert_eq!(k.raw_for(0.4), 1);
        assert_eq!(k.raw_for(1.0), 2);
        assert!((k.fraction() - 0.5).abs() < 1e-9);
    }

    #[test]
    fn ppd_names() {
        for p in [Profile::PowerSaver, Profile::Balanced, Profile::Performance] {
            assert_eq!(Profile::from_ppd(p.ppd_name()), Some(p));
        }
        assert_eq!(Profile::from_ppd("turbo"), None);
        assert_eq!(Degradation::from_ppd(""), Degradation::None);
        assert_eq!(Degradation::from_ppd("lap-detected"), Degradation::LapDetected);
        assert_eq!(Degradation::from_ppd("something-new"), Degradation::Other);
    }
}
