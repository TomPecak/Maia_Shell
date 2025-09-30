import QtQuick
import "./mask"
import "."

MainWindows{
    FontLoader {
        id: tahomaRegular
        source: "qrc:/assets/fonts/tahoma.ttf"
    }

    FontLoader {
        id: tahomaBold
        source: "qrc:/assets/fonts/tahomabd.ttf"
    }

    FontLoader {
        id: neverMindHandwriting
        source: "qrc:/assets/fonts/NeverMindHandwriting-Regular.ttf"
    }

    FontLoader {
        id: neverMindHandwritingMedium
        source: "qrc:/assets/fonts/NeverMindHandwriting-Medium.ttf"
    }
}

