#!/bin/sh
# Собирает WattPeek.app (с виджетом), проверяет, ставит в ~/Applications и запускает.
set -eu
cd "$(dirname "$0")"
# каждая строка переведена на каждый язык, иначе сборка падает
python3 -c 'import json; s=json.load(open("Shared/Localizable.xcstrings"))["strings"]
langs=set().union(*(v["localizations"] for v in s.values()))
bad=[(k,l) for k,v in s.items() for l in langs-set(v["localizations"])]
assert not bad, bad'
xcodegen generate -q
n=$(date +%Y%m%d%H%M) # новый номер, иначе система держит описание виджетов от прошлой сборки
xcodebuild -project WattPeek.xcodeproj -scheme WattPeek -configuration Debug -derivedDataPath build -quiet CURRENT_PROJECT_VERSION="$n" build
build/Build/Products/Debug/WattPeek.app/Contents/MacOS/WattPeek --check # Debug: assert'ы работают
xcodebuild -project WattPeek.xcodeproj -scheme WattPeek -configuration Release -derivedDataPath build -quiet CURRENT_PROJECT_VERSION="$n" build
codesign --verify --deep --strict build/Build/Products/Release/WattPeek.app
! grep -rqa "$HOME" build/Build/Products/Release/WattPeek.app || { echo "в сборке остался путь $HOME"; exit 1; }
mkdir -p dist && rm -f dist/*.zip
ditto -c -k --keepParent build/Build/Products/Release/WattPeek.app dist/WattPeek.zip
pkill -x WattPeek || true
app="$HOME/Applications/WattPeek.app"
rm -rf "$app"
mkdir -p "$HOME/Applications"
ditto build/Build/Products/Release/WattPeek.app "$app"
# копии из build не должны регистрироваться как второй виджет
rm -rf build/Build/Products
pkill -x WattPeekWidget || true # старый процесс жил бы со старым кодом
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
open "$app"
