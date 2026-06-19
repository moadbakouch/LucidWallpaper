/**
 * LucidWallpaper feedback receiver (Google Apps Script).
 *
 * Saves every in-app feedback report as its own Markdown file inside a Google Drive
 * folder called "Wallpaper Issues" (created automatically on the first report).
 *
 * ── SETUP (about 2 minutes) ─────────────────────────────────────────────────────────
 *  1. Go to https://script.google.com  →  New project.
 *  2. Delete the sample code, paste THIS whole file, and Save.
 *  3. Deploy  →  New deployment  →  gear icon  →  "Web app".
 *       - Description: anything
 *       - Execute as:  Me (your account)        ← so files land in YOUR Drive
 *       - Who has access:  Anyone               ← so the app can POST without a login
 *     Click Deploy, then Authorize access (review the Google warning and Allow).
 *  4. Copy the "Web app" URL it shows (it ends in /exec).
 *  5. In the app, open Sources/Settings/Feedback.swift and set:
 *         static let configuredEndpoint: URL? = URL(string: "PASTE_THE_/exec_URL_HERE")
 *     Rebuild. Done — feedback now lands in Drive → "Wallpaper Issues".
 *
 *  To change the folder name, edit FOLDER_NAME below.
 *  (When you change the script later, Deploy → Manage deployments → Edit → Version: New.)
 */

var FOLDER_NAME = 'Wallpaper Issues';

function doPost(e) {
  try {
    var data = {};
    if (e && e.postData && e.postData.contents) {
      data = JSON.parse(e.postData.contents);
    }

    var folder = getOrCreateFolder(FOLDER_NAME);

    var now = new Date();
    var stamp = Utilities.formatDate(now, Session.getScriptTimeZone(), 'yyyy-MM-dd HH-mm-ss');
    var category = sanitize(data.category || 'Feedback');
    var rand = Math.floor(Math.random() * 9000 + 1000);
    var fileName = stamp + ' - ' + category + ' - ' + rand + '.md';

    var body = [
      '# ' + category,
      '',
      '- **When:** ' + now.toISOString(),
      '- **App:** LucidWallpaper ' + (data.appVersion || '?'),
      '- **System:** ' + (data.system || '?'),
      '- **From:** ' + (data.email ? data.email : '(not provided)'),
      '- **Wallpaper:** ' + (data.wallpaper || '(none)'),
      '',
      '---',
      '',
      (data.message || '').toString()
    ].join('\n');

    folder.createFile(fileName, body, 'text/markdown');

    return json({ ok: true });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

/** A GET on the URL is handy to confirm the deployment is live. */
function doGet() {
  return json({ ok: true, service: 'LucidWallpaper feedback', folder: FOLDER_NAME });
}

function getOrCreateFolder(name) {
  var it = DriveApp.getFoldersByName(name);
  return it.hasNext() ? it.next() : DriveApp.createFolder(name);
}

function sanitize(s) {
  return String(s).replace(/[\/\\:*?"<>|]/g, '-').slice(0, 40).trim() || 'Feedback';
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
