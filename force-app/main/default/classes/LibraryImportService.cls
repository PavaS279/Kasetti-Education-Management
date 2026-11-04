/**
 * Library catalogue in bulk (Phase 5 stage 5): import a CSV of items for a
 * branch, and add copies to an existing item.
 *
 * Columns (header row, any order, case-insensitive): Title, Code, Type,
 * Author, Subject, Copies, Location, Loan days, Daily fine, Replacement cost.
 * A code the branch already has adds the copies to that item; a new code
 * creates the item. preview() shows exactly that before anything is saved.
 */
public with sharing class LibraryImportService {
  public static final Integer MAX_ROWS = 500;
  private static final Set<String> TYPES = new Set<String>{
    'Book',
    'Device',
    'Kit',
    'Media',
    'Other'
  };
  private static final Map<String, String> HEADERS = new Map<String, String>{
    'title' => 'title',
    'name' => 'title',
    'code' => 'code',
    'item code' => 'code',
    'isbn' => 'code',
    'type' => 'type',
    'item type' => 'type',
    'author' => 'author',
    'subject' => 'subject',
    'copies' => 'copies',
    'quantity' => 'copies',
    'location' => 'location',
    'shelf' => 'location',
    'loan days' => 'loanDays',
    'daily fine' => 'dailyFine',
    'fine' => 'dailyFine',
    'replacement cost' => 'replacementCost'
  };

  public class Row {
    @AuraEnabled
    public Integer line;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String itemType;
    @AuraEnabled
    public String author;
    @AuraEnabled
    public Integer copies;
    /** New, Add copies or Error. */
    @AuraEnabled
    public String action;
    @AuraEnabled
    public String message;
    public Id existingId;
    public Map<String, String> values = new Map<String, String>();
  }

  public class Preview {
    @AuraEnabled
    public List<Row> rows = new List<Row>();
    @AuraEnabled
    public Integer newItems = 0;
    @AuraEnabled
    public Integer addCopies = 0;
    @AuraEnabled
    public Integer errors = 0;
    @AuraEnabled
    public Integer copies = 0;
  }

  public class ImportResult {
    @AuraEnabled
    public Integer created = 0;
    @AuraEnabled
    public Integer updated = 0;
    @AuraEnabled
    public Integer copies = 0;
    @AuraEnabled
    public Integer skipped = 0;
  }

  private static void requireAccess() {
    if (
      !Schema.SObjectType.Library_Item__c.isCreateable() ||
      !Schema.SObjectType.Library_Item__c.isUpdateable()
    ) {
      throw new AppException('You do not have access to add library items.');
    }
  }

  public static Preview preview(Id branchId, String csv) {
    requireAccess();
    if (branchId == null) {
      throw new AppException('Choose the branch.');
    }
    List<List<String>> table = parse(csv);
    if (table.size() < 2) {
      throw new AppException(
        'The file needs a header row and at least one item.'
      );
    }
    if (table.size() - 1 > MAX_ROWS) {
      throw new AppException('Import up to ' + MAX_ROWS + ' items at a time.');
    }
    List<String> keys = new List<String>();
    for (String h : table[0]) {
      String k = HEADERS.get(h.trim().toLowerCase());
      keys.add(k == null ? '' : k);
    }
    if (!keys.contains('title') || !keys.contains('code')) {
      throw new AppException(
        'The header row needs at least Title and Code columns.'
      );
    }
    Preview p = new Preview();
    Set<String> codes = new Set<String>();
    for (Integer i = 1; i < table.size(); i++) {
      Row r = new Row();
      r.line = i + 1;
      List<String> cells = table[i];
      Boolean empty = true;
      for (Integer c = 0; c < keys.size() && c < cells.size(); c++) {
        String v = cells[c].trim();
        if (String.isNotBlank(v)) {
          empty = false;
        }
        if (String.isNotBlank(keys[c])) {
          r.values.put(keys[c], v);
        }
      }
      if (empty) {
        continue;
      }
      r.title = r.values.get('title');
      r.code = r.values.get('code') == null
        ? null
        : r.values.get('code').toUpperCase();
      r.author = r.values.get('author');
      String type = r.values.get('type');
      r.itemType = String.isBlank(type) ? 'Book' : type.capitalize();
      r.copies = 1;
      try {
        if (String.isNotBlank(r.values.get('copies'))) {
          r.copies = Integer.valueOf(r.values.get('copies'));
        }
        for (
          String num : new List<String>{
            'loanDays',
            'dailyFine',
            'replacementCost'
          }
        ) {
          if (String.isNotBlank(r.values.get(num))) {
            Decimal.valueOf(
              r.values.get(num).replace(',', '').replace('₹', '')
            );
          }
        }
      } catch (Exception e) {
        r.copies = null;
      }
      r.message = problem(r, codes);
      if (r.message != null) {
        r.action = 'Error';
        p.errors++;
      }
      if (String.isNotBlank(r.code)) {
        codes.add(r.code);
      }
      p.rows.add(r);
    }
    Map<String, Library_Item__c> existing = new Map<String, Library_Item__c>();
    for (Library_Item__c item : [
      SELECT Id, Item_Code__c, Name, Copies_Total__c
      FROM Library_Item__c
      WHERE Branch__c = :branchId AND Item_Code__c IN :codes
      WITH USER_MODE
    ]) {
      existing.put(item.Item_Code__c.toUpperCase(), item);
    }
    for (Row r : p.rows) {
      if (r.action == 'Error') {
        continue;
      }
      Library_Item__c item = existing.get(r.code);
      if (item != null) {
        r.action = 'Add copies';
        r.existingId = item.Id;
        r.message =
          item.Name +
          ': ' +
          item.Copies_Total__c.intValue() +
          ' → ' +
          (item.Copies_Total__c.intValue() + r.copies) +
          ' copies';
        p.addCopies++;
      } else {
        r.action = 'New';
        p.newItems++;
      }
      p.copies += r.copies;
    }
    return p;
  }

  private static String problem(Row r, Set<String> seen) {
    if (String.isBlank(r.title)) {
      return 'No title';
    }
    if (String.isBlank(r.code)) {
      return 'No code';
    }
    if (r.code.length() > 40) {
      return 'Code longer than 40 characters';
    }
    if (seen.contains(r.code)) {
      return 'Code repeated in the file';
    }
    if (!TYPES.contains(r.itemType)) {
      return 'Type must be Book, Device, Kit, Media or Other';
    }
    if (r.copies == null) {
      return 'Copies and amounts must be numbers';
    }
    if (r.copies < 1 || r.copies > 1000) {
      return 'Copies must be 1 to 1000';
    }
    return null;
  }

  /** Imports the rows without errors; rows with errors are skipped and counted. */
  public static ImportResult importCsv(Id branchId, String csv) {
    Preview p = preview(branchId, csv);
    ImportResult result = new ImportResult();
    List<Library_Item__c> inserts = new List<Library_Item__c>();
    Map<Id, Integer> adds = new Map<Id, Integer>();
    for (Row r : p.rows) {
      if (r.action == 'Error') {
        result.skipped++;
        continue;
      }
      result.copies += r.copies;
      if (r.action == 'Add copies') {
        adds.put(r.existingId, r.copies);
        continue;
      }
      inserts.add(
        new Library_Item__c(
          Name = r.title.left(80),
          Item_Code__c = r.code,
          Item_Type__c = r.itemType,
          Author__c = blankToNull(r.author),
          Subject__c = blankToNull(r.values.get('subject')),
          Location__c = blankToNull(r.values.get('location')),
          Copies_Total__c = r.copies,
          Loan_Days__c = number(r.values.get('loanDays')),
          Daily_Fine__c = number(r.values.get('dailyFine')),
          Replacement_Cost__c = number(r.values.get('replacementCost')),
          Branch__c = branchId,
          Active__c = true
        )
      );
    }
    Savepoint sp = Database.setSavepoint();
    try {
      Database.insert(inserts, AccessLevel.USER_MODE);
      result.created = inserts.size();
      result.updated = addCopies(adds);
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
    return result;
  }

  /** Adds copies to an existing item (new stock of the same title). */
  public static Integer addCopies(Id itemId, Integer copies) {
    requireAccess();
    if (copies == null || copies < 1 || copies > 1000) {
      throw new AppException('Add between 1 and 1000 copies.');
    }
    return addCopies(new Map<Id, Integer>{ itemId => copies });
  }

  private static Integer addCopies(Map<Id, Integer> adds) {
    if (adds.isEmpty()) {
      return 0;
    }
    List<Library_Item__c> items = [
      SELECT Id, Copies_Total__c
      FROM Library_Item__c
      WHERE Id IN :adds.keySet()
      WITH USER_MODE
      FOR UPDATE
    ];
    for (Library_Item__c item : items) {
      item.Copies_Total__c =
        (item.Copies_Total__c == null ? 0 : item.Copies_Total__c) +
        adds.get(item.Id);
    }
    Database.update(items, AccessLevel.USER_MODE);
    return items.size();
  }

  // ------------------------------------------------------------------ CSV

  /** RFC 4180 CSV: quoted fields, doubled quotes, commas and line breaks inside quotes. */
  @TestVisible
  private static List<List<String>> parse(String csv) {
    List<List<String>> rows = new List<List<String>>();
    if (String.isBlank(csv)) {
      return rows;
    }
    String text = csv.removeStart('﻿')
      .replace('\r\n', '\n')
      .replace('\r', '\n');
    List<String> row = new List<String>();
    String field = '';
    Boolean quoted = false;
    Integer n = text.length();
    for (Integer i = 0; i < n; i++) {
      String ch = text.substring(i, i + 1);
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < n && text.substring(i + 1, i + 2) == '"') {
            field += '"';
            i++;
          } else {
            quoted = false;
          }
        } else {
          field += ch;
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        row.add(field);
        field = '';
      } else if (ch == '\n') {
        row.add(field);
        rows.add(row);
        row = new List<String>();
        field = '';
      } else {
        field += ch;
      }
    }
    if (field != '' || !row.isEmpty()) {
      row.add(field);
      rows.add(row);
    }
    return rows;
  }

  private static Decimal number(String value) {
    return String.isBlank(value)
      ? null
      : Decimal.valueOf(value.replace(',', '').replace('₹', '').trim());
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }
}
