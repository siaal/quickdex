FLUTTER := fvm flutter
UV := uv run --project tool
APK := build/app/outputs/flutter-apk/app-release.apk
# Same versionCode scheme as CI (commit count), so local and CI builds update each other.
BUILD_NUMBER := $(shell git rev-list --count HEAD)

.PHONY: data test analyze run install perf

data:
	$(UV) python tool/build_data.py

test:
	$(UV) pytest tool/tests -q
	$(FLUTTER) test

analyze:
	$(UV) ruff check tool
	$(FLUTTER) analyze

run:
	$(FLUTTER) run

install:
	$(FLUTTER) build apk --release --build-number=$(BUILD_NUMBER)
	adb install -r $(APK)

perf:
	$(FLUTTER) build apk --release --build-number=$(BUILD_NUMBER) --dart-define=QUICKDEX_TRACE=true
	adb install -r $(APK)
	tool/perf.sh
