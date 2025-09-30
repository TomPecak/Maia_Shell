#pragma once

#include <QString>
#include <QStringList>
#include <QProcessEnvironment>

QStringList filterPaths(const QStringList &paths, const QString &pathToRemove);
void filterProcessEnvironment(QProcessEnvironment &env, const QString &pathToRemove);
