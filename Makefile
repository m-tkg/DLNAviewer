PROJECT := DLNAviewer.xcodeproj
SCHEME := DLNAviewer

.PHONY: help gen ota

help:
	@echo "make gen -> xcodegen generate（App/ のファイル増減後に必須）"
	@echo "make ota -> OTA 配布用 ipa/manifest.plist/index.html を作り、ota.mtkg へ配信"

gen:
	xcodegen generate

# OTA（Over-The-Air）配布。ipa + manifest.plist + index.html を作り、
# ota.mtkg（miscpi.mtkg の /mnt/storage/ota）へ ssh 配信する。
# 別サーバへ配るときは OTA_URL を渡す（例: make ota OTA_URL=https://example.com）。
ota:
	./Scripts/ota.sh $(OTA_URL)
