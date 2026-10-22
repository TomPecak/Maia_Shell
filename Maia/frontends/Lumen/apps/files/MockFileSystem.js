.pragma library

// Mock file system of the File Explorer: an in-memory tree, nothing touches the real disk.
//
// A path is a list of names joined by "/". Roots: "start" (the Home page), "home" (the home
// folder of the user), "this-pc", "network" and "trash". Every folder path has its own list
// of entries in `folders`. Changes (new folder, rename, delete, paste) only live in memory;
// the window bumps its revision after a change, so the views read the lists again.

var folders = {}
var homeLocation = "/home/user"
var userName = "user"

const day = 24 * 60 * 60 * 1000
const kib = 1024
const mib = 1024 * 1024
const gib = 1024 * 1024 * 1024

// Type name and icon (from the icon theme) by the file extension
const fileTypes = {
    "pdf": ["PDF document", "application-pdf"],
    "odt": ["Text document", "application-vnd.oasis.opendocument.text"],
    "ods": ["Spreadsheet", "application-vnd.oasis.opendocument.spreadsheet"],
    "odp": ["Presentation", "application-vnd.oasis.opendocument.presentation"],
    "txt": ["Text file", "text-plain"],
    "md": ["Markdown document", "text-markdown"],
    "jpg": ["JPEG image", "image-jpeg"],
    "png": ["PNG image", "image-png"],
    "mp3": ["MP3 audio", "audio-mpeg"],
    "flac": ["FLAC audio", "audio-x-generic"],
    "mp4": ["MP4 video", "video-mp4"],
    "mkv": ["Matroska video", "video-x-generic"],
    "zip": ["ZIP archive", "application-zip"],
    "gz": ["Compressed archive", "application-x-archive"],
    "iso": ["Disc image", "application-x-archive"],
    "py": ["Python script", "text-x-python"],
    "sh": ["Shell script", "text-x-script"],
    "AppImage": ["Application", "application-x-executable"]
}

// Folders with their own icons
const folderIcons = {
    "home": "user-home",
    "home/Desktop": "user-desktop",
    "home/Documents": "folder-documents",
    "home/Downloads": "folder-download",
    "home/Music": "folder-music",
    "home/Pictures": "folder-pictures",
    "home/Videos": "folder-videos",
    "this-pc": "computer",
    "network": "network-workgroup",
    "trash": "user-trash",
    "start": "user-home"
}

function extension(name) {
    const dot = name.lastIndexOf(".")
    return dot > 0 ? name.slice(dot + 1) : ""
}

function file(name, size, daysAgo) {
    const type = fileTypes[extension(name)] || ["File", "text-x-generic"]
    return {
        name: name, folder: false, type: type[0], icon: type[1], size: size,
        modified: Date.now() - daysAgo * day - Math.round(Math.random() * 8 * 60 * 60 * 1000)
    }
}

function folder(name, daysAgo) {
    return { name: name, folder: true, type: "File folder", icon: "folder", size: -1,
             modified: Date.now() - daysAgo * day }
}

function drive(name, mount, used, total) {
    return { name: name, folder: true, drive: true, mount: mount, type: "Local disk",
             icon: "drive-harddisk", size: total, used: used, modified: 0 }
}

// Builds the tree for the user with the given home folder
function init(home) {
    homeLocation = home && home.length > 0 ? home : "/home/user"
    userName = homeLocation.split("/").filter(part => part.length > 0).pop() || "user"

    folders = {
        "home": [
            folder("Desktop", 1), folder("Documents", 0), folder("Downloads", 0),
            folder("Music", 12), folder("Pictures", 3), folder("Videos", 20),
            file("notes.md", 3 * kib, 0), file("todo.txt", 812, 2)
        ],
        "home/Desktop": [
            file("Project plan.odt", 48 * kib, 0), file("Shopping list.txt", 512, 1),
            file("Screenshot 2026-10-12.png", 1.4 * mib, 5)
        ],
        "home/Documents": [
            folder("Projects", 1), folder("Invoices", 9), folder("Recipes", 4),
            file("Budget 2026.ods", 86 * kib, 2), file("CV.pdf", 412 * kib, 30),
            file("Letter to the bank.odt", 31 * kib, 6), file("Meeting notes.md", 9 * kib, 0),
            file("Quarterly review.odp", 3.2 * mib, 14)
        ],
        "home/Documents/Projects": [
            folder("Maia Shell", 0), folder("Website", 21),
            file("roadmap.md", 14 * kib, 1), file("ideas.txt", 2 * kib, 3)
        ],
        "home/Documents/Projects/Maia Shell": [
            folder("Screenshots", 0), file("README.md", 6 * kib, 0),
            file("Design.odp", 5.6 * mib, 2), file("build.sh", 2 * kib, 4)
        ],
        "home/Documents/Projects/Maia Shell/Screenshots": [
            file("lumen-dark.png", 2.1 * mib, 0), file("lumen-light.png", 2.3 * mib, 0),
            file("start-menu.png", 1.7 * mib, 1)
        ],
        "home/Documents/Projects/Website": [
            file("index.md", 4 * kib, 21), file("deploy.py", 3 * kib, 25)
        ],
        "home/Documents/Invoices": [
            file("Invoice 2026-08.pdf", 120 * kib, 60), file("Invoice 2026-09.pdf", 118 * kib, 30),
            file("Invoice 2026-10.pdf", 121 * kib, 9)
        ],
        "home/Documents/Recipes": [
            file("Soft boiled eggs.txt", 1 * kib, 4), file("Pancakes.pdf", 260 * kib, 40),
            file("Tomato soup.odt", 22 * kib, 18)
        ],
        "home/Downloads": [
            file("ubuntu-24.04-desktop-amd64.iso", 5.7 * gib, 3), file("manual.pdf", 7.8 * mib, 1),
            file("wallpaper-4k.jpg", 9.2 * mib, 0), file("Krita.AppImage", 312 * mib, 8),
            file("photos-backup.zip", 1.3 * gib, 15), file("song.mp3", 6.4 * mib, 2)
        ],
        "home/Music": [
            folder("Jazz", 40), folder("Rock", 55),
            file("Morning playlist.mp3", 8.1 * mib, 12), file("Rainy day.flac", 31 * mib, 12)
        ],
        "home/Music/Jazz": [
            file("Blue in green.flac", 28 * mib, 40), file("So what.mp3", 9.4 * mib, 40)
        ],
        "home/Music/Rock": [
            file("Highway.mp3", 7.6 * mib, 55)
        ],
        "home/Pictures": [
            folder("Holidays 2026", 3), folder("Screenshots", 5),
            file("Cat.jpg", 3.4 * mib, 7), file("Mountains.jpg", 5.1 * mib, 3),
            file("Family dinner.jpg", 4.2 * mib, 10)
        ],
        "home/Pictures/Holidays 2026": [
            file("Beach.jpg", 4.8 * mib, 3), file("Sunset.jpg", 5.2 * mib, 3),
            file("Old town.jpg", 4.4 * mib, 4), file("Harbour.jpg", 4.9 * mib, 4)
        ],
        "home/Pictures/Screenshots": [
            file("Screenshot 2026-10-05.png", 1.1 * mib, 13), file("Screenshot 2026-10-11.png", 1.3 * mib, 7)
        ],
        "home/Videos": [
            file("Birthday.mp4", 820 * mib, 20), file("Timelapse.mkv", 1.9 * gib, 34)
        ],
        "this-pc": [
            drive("System", "/", 61 * gib, 237 * gib),
            drive("Data", "/mnt/data", 702 * gib, 931 * gib),
            drive("USB drive", "/media/usb", 3.1 * gib, 29 * gib)
        ],
        "network": [],
        "trash": [
            file("old draft.odt", 18 * kib, 11), file("blurry photo.jpg", 2.2 * mib, 6)
        ]
    }

    // Drives contain the home folder (System) or nothing
    folders["this-pc/System"] = [folder("home", 30), folder("usr", 90), folder("etc", 90)]
    folders["this-pc/System/home"] = [folder(userName, 1)]
    folders["this-pc/System/usr"] = []
    folders["this-pc/System/etc"] = []
    folders["this-pc/System/home/" + userName] = []
    folders["this-pc/Data"] = [folder("Backups", 15), folder("Games", 70)]
    folders["this-pc/Data/Backups"] = []
    folders["this-pc/Data/Games"] = []
    folders["this-pc/USB drive"] = [file("presentation.odp", 4.1 * mib, 2)]
}

// --- Reading ---

function exists(path) {
    return path === "start" || folders.hasOwnProperty(path)
}

function children(path) {
    const list = folders[path]
    return list ? list.slice() : []
}

function parent(path) {
    const slash = path.lastIndexOf("/")
    return slash > 0 ? path.slice(0, slash) : ""
}

function join(path, name) {
    return path + "/" + name
}

function displayName(path) {
    switch (path) {
    case "start": return "Home"
    case "home": return userName
    case "this-pc": return "This PC"
    case "network": return "Network"
    case "trash": return "Recycle Bin"
    }
    return path.slice(path.lastIndexOf("/") + 1)
}

function iconFor(path) {
    if (folderIcons[path])
        return folderIcons[path]
    if (parent(path) === "this-pc")
        return "drive-harddisk"
    return "folder"
}

// Icon of an entry inside the given folder
function entryIcon(path, entry) {
    return entry.folder ? iconFor(join(path, entry.name)) : entry.icon
}

// Breadcrumb of the path: [{ name, path }]
function segments(path) {
    if (path === "start")
        return [{ name: "Home", path: "start" }]
    const parts = path.split("/")
    const result = []
    for (let i = 0; i < parts.length; i++) {
        const p = parts.slice(0, i + 1).join("/")
        result.push({ name: displayName(p), path: p })
    }
    return result
}

// Location shown in the address bar while editing, e.g. /home/user/Documents
function toLocation(path) {
    if (path === "home" || path.startsWith("home/"))
        return homeLocation + path.slice(4)
    if (path.startsWith("this-pc/System"))
        return "/" + path.slice("this-pc/System".length + 1)
    if (path === "this-pc")
        return "This PC"
    if (path === "trash")
        return "Recycle Bin"
    if (path === "network")
        return "Network"
    return displayName(path)
}

// Path of a location typed into the address bar, "" when it does not exist
function fromLocation(text) {
    let location = text.trim()
    if (location.length > 1 && location.endsWith("/"))
        location = location.slice(0, -1)
    const lower = location.toLowerCase()
    const named = { "home": "start", "this pc": "this-pc", "recycle bin": "trash", "trash": "trash", "network": "network" }
    if (named[lower])
        return named[lower]
    if (location === "~")
        return "home"
    if (location.startsWith("~/"))
        location = homeLocation + location.slice(1)
    if (location === homeLocation || location.startsWith(homeLocation + "/")) {
        const path = "home" + location.slice(homeLocation.length)
        return exists(path) ? path : ""
    }
    if (location === "/")
        return "this-pc/System"
    if (location.startsWith("/")) {
        const path = "this-pc/System" + location
        return exists(path) ? path : ""
    }
    return ""
}

// Files and folders whose name contains the query, under the given folder
function search(path, query) {
    const results = []
    const needle = query.toLowerCase()
    const roots = path === "start" ? ["home"] : [path]
    const visit = folderPath => {
        const list = folders[folderPath] || []
        for (const entry of list) {
            if (entry.name.toLowerCase().indexOf(needle) >= 0)
                results.push(Object.assign({}, entry, { location: folderPath }))
            if (entry.folder)
                visit(join(folderPath, entry.name))
        }
    }
    roots.forEach(visit)
    return results
}

// Recently changed files of the home folder, newest first
function recent(count) {
    const results = []
    const visit = folderPath => {
        for (const entry of folders[folderPath] || []) {
            if (entry.folder)
                visit(join(folderPath, entry.name))
            else
                results.push(Object.assign({}, entry, { location: folderPath }))
        }
    }
    visit("home")
    results.sort((a, b) => b.modified - a.modified)
    return results.slice(0, count)
}

// Folders shown in Quick access
function quickAccess() {
    return ["home/Desktop", "home/Downloads", "home/Documents", "home/Pictures", "home/Music", "home/Videos"]
}

// --- Changes ---

function uniqueName(path, base) {
    const list = folders[path] || []
    const taken = name => list.some(entry => entry.name === name)
    if (!taken(base))
        return base
    const ext = extension(base)
    const stem = ext.length > 0 ? base.slice(0, -(ext.length + 1)) : base
    for (let i = 2; ; i++) {
        const candidate = stem + " (" + i + ")" + (ext.length > 0 ? "." + ext : "")
        if (!taken(candidate))
            return candidate
    }
}

function canModify(path) {
    return folders.hasOwnProperty(path) && path !== "this-pc" && path !== "network"
}

// Creates a new folder or file and returns its name ("" when not possible)
function create(path, baseName, isFolder) {
    if (!canModify(path))
        return ""
    const name = uniqueName(path, baseName)
    folders[path].push(isFolder ? folder(name, 0) : file(name, 0, 0))
    if (isFolder)
        folders[join(path, name)] = []
    return name
}

function moveTree(from, to) {
    for (const key of Object.keys(folders)) {
        if (key === from || key.startsWith(from + "/")) {
            folders[to + key.slice(from.length)] = folders[key]
            delete folders[key]
        }
    }
}

function copyTree(from, to) {
    for (const key of Object.keys(folders)) {
        if (key === from || key.startsWith(from + "/"))
            folders[to + key.slice(from.length)] = folders[key].map(entry => Object.assign({}, entry))
    }
}

function rename(path, oldName, newName) {
    const name = newName.trim()
    const list = folders[path] || []
    const entry = list.find(item => item.name === oldName)
    if (!entry || name.length === 0 || name.indexOf("/") >= 0)
        return false
    if (name === oldName)
        return true
    if (list.some(item => item.name === name))
        return false
    if (entry.folder)
        moveTree(join(path, oldName), join(path, name))
    entry.name = name
    if (!entry.folder) {
        const type = fileTypes[extension(name)] || ["File", "text-x-generic"]
        entry.type = type[0]
        entry.icon = type[1]
    }
    entry.modified = Date.now()
    return true
}

// Moves the entries to the Recycle Bin (inside the Recycle Bin: deletes them)
function remove(path, names) {
    if (!canModify(path))
        return 0
    const list = folders[path]
    let count = 0
    for (const name of names) {
        const index = list.findIndex(item => item.name === name)
        if (index < 0)
            continue
        const entry = list.splice(index, 1)[0]
        if (path !== "trash") {
            const trashName = uniqueName("trash", entry.name)
            if (entry.folder)
                moveTree(join(path, entry.name), join("trash", trashName))
            folders["trash"].push(Object.assign(entry, { name: trashName, modified: Date.now() }))
        } else if (entry.folder) {
            for (const key of Object.keys(folders)) {
                if (key === join(path, name) || key.startsWith(join(path, name) + "/"))
                    delete folders[key]
            }
        }
        count++
    }
    return count
}

// Pastes the clipboard ({ from, names, cut }) into the folder, returns the number of items
function paste(path, clipboard) {
    if (!canModify(path) || !clipboard)
        return 0
    const source = folders[clipboard.from] || []
    let count = 0
    for (const name of clipboard.names) {
        const entry = source.find(item => item.name === name)
        if (!entry)
            continue
        if (entry.folder && (path === join(clipboard.from, name) || path.startsWith(join(clipboard.from, name) + "/")))
            continue // a folder into itself
        if (clipboard.cut && clipboard.from === path)
            continue
        const newName = uniqueName(path, entry.name)
        const copy = Object.assign({}, entry, { name: newName, modified: Date.now() })
        if (entry.folder) {
            if (clipboard.cut)
                moveTree(join(clipboard.from, name), join(path, newName))
            else
                copyTree(join(clipboard.from, name), join(path, newName))
        }
        folders[path].push(copy)
        if (clipboard.cut)
            source.splice(source.indexOf(entry), 1)
        count++
    }
    return count
}

// --- Formatting ---

function formatSize(bytes) {
    if (bytes < 0)
        return ""
    if (bytes < kib)
        return Math.round(bytes) + " B"
    const units = ["KB", "MB", "GB", "TB"]
    let value = bytes / kib
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024
        unit++
    }
    return (value < 10 ? value.toFixed(1) : Math.round(value)) + " " + units[unit]
}

function formatDate(ms, locale) {
    if (!ms)
        return ""
    return new Date(ms).toLocaleString(locale, "dd.MM.yyyy HH:mm")
}

// Readable time since the change, for the Recent list
function formatRelative(ms) {
    const minutes = Math.round((Date.now() - ms) / 60000)
    if (minutes < 60)
        return minutes <= 1 ? "Just now" : minutes + " minutes ago"
    const hours = Math.round(minutes / 60)
    if (hours < 24)
        return hours === 1 ? "An hour ago" : hours + " hours ago"
    const days = Math.round(hours / 24)
    return days === 1 ? "Yesterday" : days + " days ago"
}
