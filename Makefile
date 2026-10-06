FLUTTER := fvm flutter
UV := uv run --project tool
APK := build/app/outputs/flutter-apk/app-release.apk

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
	$(FLUTTER) build apk --release
	adb install -r $(APK)

perf:
	$(FLUTTER) build apk --release --dart-define=QUICKDEX_TRACE=true
	adb install -r $(APK)
	tool/perf.sh
