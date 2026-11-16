#pragma once

// The files of a notification (Notification.urls: a screenshot, a download, a file from a phone) as
// a shell shows them: a name, the MIME type and its icon names, and a preview.
//
// Read once per notification, in the connection's KJ thread (never the GUI thread): the MIME type
// from the name (no file is opened), one stat per file, one per cached thumbnail.
//
// The preview, in order:
//   1. a fresh picture of the freedesktop thumbnail cache ($XDG_CACHE_HOME/thumbnails/<size>/
//      <md5 of the URI>.png, not older than the file): what file managers made for PDFs, videos,
//      photos;
//   2. the file itself when it is a local image not larger than kMaxPreviewBytes (a screenshot);
//   3. none: the shell shows the MIME type's icon.
// A shell decodes a preview asynchronously at its shown size (Image { asynchronous: true;
// sourceSize: … }); one that fails shows the icon.

#include <QList>
#include <QString>

namespace MaiaNotifications {

struct FileData {
    QString url;             // as the service gave it (file://, https://, smb://, …)
    QString name;            // the file name, or the host for a URL without one
    QString mimeType;        // from the name, "application/octet-stream" unknown
    QString iconName;        // the MIME type's icon ("image-png"), and the generic one of its
    QString genericIconName; // group ("image-x-generic") for an icon theme without it
    QString preview;         // a file:// URL of a picture to show, "" none
    bool local = false;      // a file:// URL
    bool exists = false;     // a local file that is there (false for other URLs)
    bool image = false;      // an image type (the file itself may be the preview)

    bool operator==(const FileData &) const = default;
};

// A local image larger than this is not its own preview (decoding it would take long)
constexpr qint64 kMaxPreviewBytes = 40 * 1024 * 1024;

FileData readFile(const QString &url);
QList<FileData> readFiles(const QStringList &urls);

// The freshest picture of `fileUrl` in the thumbnail cache (largest size first), "" none. A
// picture older than the file (`fileModified`, ms since 1970) is stale.
QString cachedThumbnail(const QString &fileUrl, qint64 fileModified);

} // namespace MaiaNotifications
