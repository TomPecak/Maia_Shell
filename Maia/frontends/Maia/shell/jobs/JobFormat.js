.pragma library

// What a job (a row of JobsModel) says in words. Plain functions of its values, so they are the same
// in the pill and in the notification center.

// What a card shows for a row that is already gone (the model removes it before the card)
const emptyJob = Object.freeze({
    jobId: 0, appName: "", desktopEntry: "", appIcon: "", title: "", infoMessage: "", state: 2, percent: -1,
    processedBytes: 0, totalBytes: 0, processedFiles: 0, totalFiles: 0, processedDirectories: 0,
    totalDirectories: 0, processedItems: 0, totalItems: 0, speed: 0, destination: "",
    errorText: "", ownerGone: false, killable: false, suspendable: false
})

function size(bytes) {
    return Qt.locale().formattedDataSize(bytes)
}

// "20 s left", "3 min left", "1 h 5 min left"; never "60 min"
function timeLeft(seconds) {
    if (seconds < 60)
        return qsTr("%1 s left").arg(Math.max(1, Math.round(seconds)))
    const minutes = Math.ceil(seconds / 60)
    if (minutes < 60)
        return qsTr("%1 min left").arg(minutes)
    const rest = minutes % 60
    return rest === 0 ? qsTr("%1 h left").arg(minutes / 60)
                      : qsTr("%1 h %2 min left").arg(Math.floor(minutes / 60)).arg(rest)
}

function title(job) {
    return job.title.length > 0 ? job.title : qsTr("Working")
}

// What the job counts, the most telling first: "%1 of %2" in bytes, else files, items (an archive,
// a deletion), folders; "" when it counts nothing of more than one
function amount(job) {
    if (job.totalBytes > 0)
        return qsTr("%1 of %2").arg(size(job.processedBytes)).arg(size(job.totalBytes))
    if (job.totalFiles > 1)
        return qsTr("%1 of %2 files").arg(job.processedFiles).arg(job.totalFiles)
    if ((job.totalItems ?? 0) > 1)
        return qsTr("%1 of %2 items").arg(job.processedItems).arg(job.totalItems)
    if ((job.totalDirectories ?? 0) > 1)
        return qsTr("%1 of %2 folders").arg(job.processedDirectories).arg(job.totalDirectories)
    return ""
}

// "400 MB of 1 GB · 25 MB/s · 20 s left", or what is known of it
function progress(job) {
    const parts = []
    const counted = amount(job)
    if (counted.length > 0)
        parts.push(counted)
    if (job.state === 1) {
        parts.push(qsTr("Paused"))
    } else if (job.speed > 0) {
        parts.push(qsTr("%1/s").arg(size(job.speed)))
        if (job.totalBytes > job.processedBytes)
            parts.push(timeLeft((job.totalBytes - job.processedBytes) / job.speed))
    }
    return parts.join(" · ")
}

// How it ended
function ended(job) {
    if (job.state === 3) {
        if (job.ownerGone)
            return qsTr("%1 closed before it was done.").arg(job.appName.length > 0 ? job.appName : qsTr("The application"))
        return job.errorText.length > 0 ? job.errorText : qsTr("It did not succeed.")
    }
    if (job.totalBytes > 0)
        return qsTr("Done, %1").arg(size(job.totalBytes))
    if (job.totalFiles > 1)
        return qsTr("Done, %1 files").arg(job.totalFiles)
    if ((job.totalItems ?? 0) > 1)
        return qsTr("Done, %1 items").arg(job.totalItems)
    if ((job.totalDirectories ?? 0) > 1)
        return qsTr("Done, %1 folders").arg(job.totalDirectories)
    return qsTr("Done")
}

// What the pill says after the title: the share, or how it ended
function shortState(job) {
    if (job.state === 2)
        return qsTr("Done")
    if (job.state === 3)
        return qsTr("Failed")
    if (job.state === 1)
        return qsTr("Paused")
    return job.percent >= 0 ? qsTr("%1 %").arg(job.percent) : ""
}

// A URL for xdg-open: encoded, as the command is split on spaces
function folderUrl(destination) {
    return destination.indexOf("%") >= 0 ? destination.replace(/ /g, "%20") : encodeURI(destination)
}
