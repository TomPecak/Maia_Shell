pragma Singleton

import Maia.CrossProcessState

// The way a frontend declares its state: one singleton, used by name in every process
CrossProcessState {
    category: "TestSingleton"

    property string text: "default"
    property int count: 0
    // Derived, in each process, from what is shared
    readonly property string shout: text.toUpperCase()

    signal ping(int number)
}
