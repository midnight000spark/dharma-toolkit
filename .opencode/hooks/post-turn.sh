#!/bin/bash
# Автозапуск flutter analyze после каждого хода агента
flutter analyze --fatal-infos 0 || exit 1
