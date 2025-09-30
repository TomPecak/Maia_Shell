#include "Process.hpp"

#include <QDir>

QStringList filterPaths(const QStringList &paths, const QString &pathToRemove) {
    QStringList filteredPaths;
    for (const QString &path : paths) {
        if (!path.contains(pathToRemove)) {
            filteredPaths.append(path);
        }
    }
    return filteredPaths;
}

void filterProcessEnvironment(QProcessEnvironment &env, const QString &pathToRemove) {
    QString separator = QDir::listSeparator();

    for (const QString &var : env.keys()) {
        QString value = env.value(var);

        if (value.contains(pathToRemove) && value.contains(separator)) {
            QStringList paths = value.split(separator, Qt::SkipEmptyParts);
            QStringList filteredPaths = filterPaths(paths, pathToRemove);
            env.insert(var, filteredPaths.join(separator));
        } else if (value == pathToRemove) {
            env.remove(var);
        }
    }
}
