import 'dart:convert';

bool validJournalCsvDownload(String csv, String filename) =>
    csv.startsWith('\uFEFF"closeTimeUtc",') &&
    csv.endsWith('\r\n') &&
    csv.length <= 10 * 1024 * 1024 &&
    utf8.encode(csv).length <= 10 * 1024 * 1024 &&
    RegExp(
          r'^protrading-journal-\d{4}-\d{2}-\d{2}\.csv$',
        ).stringMatch(filename) ==
        filename;
