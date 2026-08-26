#!/bin/bash
DATE=$(date +%Y-%m-%d)
STAGE=$1
STATUS=$2

# Добавляет запись в журнал изменений STATE.md
echo "| $DATE | Этап $STAGE: $STATUS | Big Pickle |" >> STATE.md
