---

excalidraw-plugin: parsed
tags: [excalidraw]

---
==⚠  Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document. ⚠== You can decompress Drawing data with the command palette: 'Decompress current Excalidraw file'. For more info check in plugin settings under 'Saving'


# Excalidraw Data

## Text Elements
User ^UserText

email 一意 🔑 ^EmailTxt

DB の unique index も確認 ^MemoText

## Element Links
EmailBox: omoteura:#email 一意であること

DocsLink: https://example.com/docs

%%
## Drawing
```json
{
	"type": "excalidraw",
	"version": 2,
	"source": "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/tag/2.29.0",
	"elements": [
		{
			"id": "UserBox1",
			"type": "rectangle",
			"isDeleted": false,
			"link": null,
			"boundElements": [
				{
					"type": "text",
					"id": "UserText"
				}
			]
		},
		{
			"id": "UserText",
			"type": "text",
			"isDeleted": false,
			"link": null,
			"text": "User",
			"rawText": "User",
			"originalText": "User",
			"containerId": "UserBox1"
		},
		{
			"id": "EmailBox",
			"type": "rectangle",
			"isDeleted": false,
			"link": "omoteura:#email 一意であること",
			"boundElements": [
				{
					"type": "text",
					"id": "EmailTxt"
				}
			]
		},
		{
			"id": "EmailTxt",
			"type": "text",
			"isDeleted": false,
			"link": null,
			"text": "email 一意 🔑",
			"rawText": "email 一意 🔑",
			"originalText": "email 一意 🔑",
			"containerId": "EmailBox"
		},
		{
			"id": "MemoText",
			"type": "text",
			"isDeleted": false,
			"link": null,
			"text": "DB の unique index も確認",
			"rawText": "DB の unique index も確認",
			"originalText": "DB の unique index も確認",
			"containerId": null
		},
		{
			"id": "DocsLink",
			"type": "rectangle",
			"isDeleted": false,
			"link": "https://example.com/docs",
			"boundElements": null
		},
		{
			"id": "Removed1",
			"type": "rectangle",
			"isDeleted": true,
			"link": "omoteura:#削除済み",
			"boundElements": null
		}
	],
	"appState": {
		"viewBackgroundColor": "#ffffff"
	},
	"files": {}
}
```
%%