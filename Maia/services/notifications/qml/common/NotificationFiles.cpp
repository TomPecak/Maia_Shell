#include "NotificationFiles.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QStandardPaths>
#include <QUrl>

namespace MaiaNotifications {

QString cachedThumbnail(const QString &fileUrl, qint64 fileModified)
{
    // The cache names a picture by the MD5 of the file's URI (the freedesktop thumbnail spec)
    const QByteArray uri = QUrl(fileUrl).toEncoded(QUrl::FullyEncoded);
    const QString name = QString::fromLatin1(QCryptographicHash::hash(uri, QCryptographicHash::Md5).toHex()) + QStringLiteral(".png");
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/thumbnails/");
    // Sharp on a 2x screen first, the smallest last
    for (const char *size : {"x-large", "large", "xx-large", "normal"}) {
        const QFileInfo picture(cache + QLatin1String(size) + QLatin1Char('/') + name);
        if (picture.isFile() && picture.lastModified().toMSecsSinceEpoch() >= fileModified)
            return QUrl::fromLocalFile(picture.absoluteFilePath()).toString(QUrl::FullyEncoded);
    }
    return {};
}

FileData readFile(const QString &url)
{
    static const QMimeDatabase mimeDatabase;
    FileData file;
    file.url = url;
    const QUrl parsed(url);
    file.local = parsed.isLocalFile();
    const QString path = file.local ? parsed.toLocalFile() : parsed.path();
    file.name = parsed.fileName(QUrl::FullyDecoded);
    if (file.name.isEmpty())
        file.name = parsed.host().isEmpty() ? url : parsed.host();

    const QMimeType mime = mimeDatabase.mimeTypeForFile(path, QMimeDatabase::MatchExtension);
    file.mimeType = mime.name();
    file.iconName = mime.iconName();
    file.genericIconName = mime.genericIconName();
    file.image = file.mimeType.startsWith(QLatin1String("image/"));

    if (file.local) {
        const QFileInfo info(path);
        file.exists = info.isFile();
        if (file.exists) {
            file.preview = cachedThumbnail(url, info.lastModified().toMSecsSinceEpoch());
            if (file.preview.isEmpty() && file.image && info.size() <= kMaxPreviewBytes)
                file.preview = url;
        }
    }
    return file;
}

QList<FileData> readFiles(const QStringList &urls)
{
    QList<FileData> files;
    files.reserve(urls.size());
    for (const QString &url : urls)
        files.append(readFile(url));
    return files;
}

} // namespace MaiaNotifications
