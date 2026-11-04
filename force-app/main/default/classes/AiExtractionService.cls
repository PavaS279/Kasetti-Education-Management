/**
 * AI document reader for admissions (F4.7).
 *
 * Staff pick a document attached to an application (or upload or paste
 * one); the browser turns a PDF into text (pdf.js, no file leaves
 * Salesforce except through the Einstein Trust Layer), and Einstein reads
 * the text into a fixed set of fields. Each field comes back as a proposal
 * next to the value already on the record; nothing is saved until staff
 * tick the proposals they confirm and press Apply. Scanned images are not
 * supported (no OCR): the panel says so.
 *
 * What staff apply is compared with what was proposed to measure accuracy
 * (AI interaction outcome and edit ratio).
 */
public with sharing class AiExtractionService {
  public static final String PROMPT = 'Document_Extraction';
  public static final Integer MAX_TEXT = 12000;
  public static final Integer MAX_FILE_BYTES = 4 * 1024 * 1024;
  public static final Set<String> TEXT_TYPES = new Set<String>{
    'TEXT',
    'CSV',
    'TXT'
  };

  /** One field the reader looks for. */
  private class Def {
    String key;
    String label;
    String section;
    Def(String key, String label, String section) {
      this.key = key;
      this.label = label;
      this.section = section;
    }
  }

  private static final List<Def> DEFS = new List<Def>{
    new Def('learnerFirstName', 'First name', 'Learner'),
    new Def('learnerLastName', 'Last name', 'Learner'),
    new Def('dateOfBirth', 'Date of birth', 'Learner'),
    new Def('learnerEmail', 'Email', 'Learner'),
    new Def('learnerPhone', 'Mobile', 'Learner'),
    new Def('street', 'Street', 'Address'),
    new Def('city', 'City', 'Address'),
    new Def('postalCode', 'Postal code', 'Address'),
    new Def('guardianFirstName', 'Guardian first name', 'Guardian'),
    new Def('guardianLastName', 'Guardian last name', 'Guardian'),
    new Def('guardianRelationship', 'Relationship', 'Guardian'),
    new Def('guardianPhone', 'Guardian phone', 'Guardian'),
    new Def('guardianEmail', 'Guardian email', 'Guardian'),
    new Def('previousSchool', 'Previous school', 'Education'),
    new Def('previousGrade', 'Previous grade or class', 'Education')
  };

  public class Document {
    @AuraEnabled
    public Id contentVersionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String fileType;
    @AuraEnabled
    public Integer sizeKb;
    @AuraEnabled
    public String attachedTo;
    @AuraEnabled
    public Boolean readable;
    @AuraEnabled
    public String reason;
  }

  public class FileContent {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String text;
    @AuraEnabled
    public String base64;
    @AuraEnabled
    public String title;
  }

  public class Proposal {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String section;
    @AuraEnabled
    public String current;
    @AuraEnabled
    public String proposed;
    @AuraEnabled
    public Boolean differs = false;
    @AuraEnabled
    public Boolean selectable = true;
    @AuraEnabled
    public Boolean selected = false;
    @AuraEnabled
    public String note;
  }

  public class Extraction {
    @AuraEnabled
    public Id interactionId;
    @AuraEnabled
    public String documentType;
    @AuraEnabled
    public String documentName;
    @AuraEnabled
    public List<Proposal> proposals = new List<Proposal>();
    @AuraEnabled
    public Integer found = 0;
    @AuraEnabled
    public Boolean truncated = false;
    @AuraEnabled
    public Boolean hasGuardian = false;
  }

  public class Change {
    @AuraEnabled
    public String key { get; set; }
    @AuraEnabled
    public String value { get; set; }
  }

  public class ApplyResult {
    @AuraEnabled
    public Integer learnerFields = 0;
    @AuraEnabled
    public Boolean guardianAdded = false;
    @AuraEnabled
    public Integer guardianFields = 0;
    @AuraEnabled
    public Boolean detailsNoted = false;
    @AuraEnabled
    public String outcome;
  }

  // ---------------------------------------------------------------- documents

  /** Files on the application and its checklist items that the user can open. */
  public static List<Document> documents(Id applicationId) {
    IndividualApplication app = application(applicationId);
    Map<Id, String> parents = new Map<Id, String>{ app.Id => 'Application' };
    for (DocumentChecklistItem item : [
      SELECT Id, Name
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :app.Id
      WITH USER_MODE
    ]) {
      parents.put(item.Id, item.Name);
    }
    Map<Id, String> attachedTo = new Map<Id, String>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :parents.keySet()
      WITH USER_MODE
    ]) {
      attachedTo.put(link.ContentDocumentId, parents.get(link.LinkedEntityId));
    }
    List<Document> result = new List<Document>();
    if (attachedTo.isEmpty()) {
      return result;
    }
    for (ContentVersion v : [
      SELECT Id, Title, FileType, ContentSize, ContentDocumentId
      FROM ContentVersion
      WHERE ContentDocumentId IN :attachedTo.keySet() AND IsLatest = TRUE
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 50
    ]) {
      Document d = new Document();
      d.contentVersionId = v.Id;
      d.title = v.Title;
      d.fileType = v.FileType;
      d.sizeKb = v.ContentSize == null ? 0 : (v.ContentSize / 1024);
      d.attachedTo = attachedTo.get(v.ContentDocumentId);
      String type = v.FileType == null ? '' : v.FileType.toUpperCase();
      if (type != 'PDF' && !TEXT_TYPES.contains(type)) {
        d.readable = false;
        d.reason = 'Only PDF and text files can be read (scanned images need OCR).';
      } else if (v.ContentSize != null && v.ContentSize > MAX_FILE_BYTES) {
        d.readable = false;
        d.reason = 'Larger than 4 MB.';
      } else {
        d.readable = true;
      }
      result.add(d);
    }
    return result;
  }

  /** Returns a text file's text, or a PDF's bytes for the browser to read. */
  public static FileContent fileContent(Id contentVersionId) {
    List<ContentVersion> rows = [
      SELECT Id, Title, FileType, ContentSize, VersionData
      FROM ContentVersion
      WHERE Id = :contentVersionId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Document not found.');
    }
    ContentVersion v = rows[0];
    if (v.ContentSize != null && v.ContentSize > MAX_FILE_BYTES) {
      throw new AppException('The document is larger than 4 MB.');
    }
    String type = v.FileType == null ? '' : v.FileType.toUpperCase();
    FileContent c = new FileContent();
    c.title = v.Title;
    if (type == 'PDF') {
      c.kind = 'pdf';
      c.base64 = EncodingUtil.base64Encode(v.VersionData);
    } else if (TEXT_TYPES.contains(type)) {
      c.kind = 'text';
      c.text = v.VersionData.toString().left(MAX_TEXT * 2);
    } else {
      throw new AppException(
        'Only PDF and text files can be read. Scanned images need OCR, which is not available.'
      );
    }
    return c;
  }

  // ---------------------------------------------------------------- extraction

  /** Reads the text with Einstein and returns proposals next to current values. */
  public static Extraction extract(
    Id applicationId,
    String documentName,
    String text
  ) {
    IndividualApplication app = application(applicationId);
    String clean = text == null
      ? ''
      : text.replaceAll('[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F]', ' ')
          .replaceAll('[ \\t]{2,}', ' ')
          .trim();
    if (clean.length() < 20) {
      throw new AppException(
        'The document has no readable text. If it is a scan or photo, type the details instead.'
      );
    }
    Extraction result = new Extraction();
    result.documentName = String.isBlank(documentName)
      ? 'Pasted text'
      : documentName.left(120);
    result.truncated = clean.length() > MAX_TEXT;
    AiService.Result generated = AiService.generateOrFail(
      PROMPT,
      new Map<String, String>{
        'DocumentName' => result.documentName,
        'DocumentText' => clean.left(MAX_TEXT)
      },
      app.Id,
      app.Branch__c
    );
    result.interactionId = generated.interactionId;
    Map<String, Object> data;
    try {
      data = AiJson.parseObject(generated.text);
    } catch (Exception e) {
      throw new AppException(
        'The AI reader did not return usable details. Please try again.'
      );
    }
    result.documentType = value(data, 'documentType');
    Current current = currentValues(app);
    result.hasGuardian = current.guardianAccountId != null;
    // A document naming another parent must not update the linked guardian.
    Boolean otherPerson =
      result.hasGuardian &&
      (differentValue(
        current.values.get('guardianFirstName'),
        value(data, 'guardianFirstName')
      ) ||
      differentValue(
        current.values.get('guardianRelationship'),
        relationship(value(data, 'guardianRelationship'))
      ));
    for (Def d : DEFS) {
      Proposal p = new Proposal();
      p.key = d.key;
      p.label = d.label;
      p.section = d.section;
      p.current = current.values.get(d.key);
      p.proposed = normalise(d.key, value(data, d.key));
      if (String.isBlank(p.proposed)) {
        continue;
      }
      result.found++;
      p.differs = !same(p.current, p.proposed);
      if (d.section == 'Guardian' && current.guardianAccountId != null) {
        // Existing guardians keep their names; contact details can be updated.
        p.selectable =
          !otherPerson &&
          (d.key == 'guardianPhone' ||
          d.key == 'guardianEmail');
        if (otherPerson && p.differs) {
          p.note = 'The document names a different parent or guardian: add them from the learner record if needed.';
        } else if (!p.selectable && p.differs) {
          p.note = 'Different from the linked guardian: check the guardian record.';
        }
      }
      if (d.key == 'dateOfBirth' && p.proposed != null && !isDate(p.proposed)) {
        p.selectable = false;
        p.note = 'Not a clear date: enter it on the learner record.';
      }
      // Pre-tick only values that fill a blank; staff decide on conflicts.
      p.selected = p.selectable && p.differs && String.isBlank(p.current);
      if (p.differs && String.isNotBlank(p.current) && p.note == null) {
        p.note = 'Differs from the record: tick to replace.';
      }
      result.proposals.add(p);
    }
    if (result.interactionId != null) {
      // Store the proposals in a comparable form for measuring edits.
      AiService.replaceResponse(
        result.interactionId,
        describe(result.proposals)
      );
    }
    return result;
  }

  // ---------------------------------------------------------------- apply

  /** Saves the proposals staff confirmed (values may have been corrected). */
  public static ApplyResult apply(
    Id applicationId,
    Id interactionId,
    String documentName,
    List<Change> changes
  ) {
    IndividualApplication app = application(applicationId);
    Map<String, String> values = new Map<String, String>();
    Set<String> known = new Set<String>();
    for (Def d : DEFS) {
      known.add(d.key);
    }
    for (Change c : changes == null ? new List<Change>() : changes) {
      if (c == null || !known.contains(c.key) || String.isBlank(c.value)) {
        continue;
      }
      values.put(c.key, c.value.trim());
    }
    if (values.isEmpty()) {
      throw new AppException('Tick at least one detail to apply.');
    }
    validate(values);
    Current current = currentValues(app);
    ApplyResult result = new ApplyResult();

    Account learner = new Account(Id = app.AccountId);
    Map<String, String> learnerFields = new Map<String, String>{
      'learnerFirstName' => 'FirstName',
      'learnerLastName' => 'LastName',
      'learnerEmail' => 'PersonEmail',
      'learnerPhone' => 'PersonMobilePhone',
      'street' => 'PersonMailingStreet',
      'city' => 'PersonMailingCity',
      'postalCode' => 'PersonMailingPostalCode'
    };
    for (String key : learnerFields.keySet()) {
      if (values.containsKey(key)) {
        learner.put(learnerFields.get(key), values.get(key));
        result.learnerFields++;
      }
    }
    if (values.containsKey('dateOfBirth')) {
      learner.put('PersonBirthdate', Date.valueOf(values.get('dateOfBirth')));
      result.learnerFields++;
    }
    Savepoint sp = Database.setSavepoint();
    try {
      if (result.learnerFields > 0) {
        Database.update(learner, AccessLevel.USER_MODE);
      }
      Boolean guardianGiven =
        values.containsKey('guardianLastName') ||
        values.containsKey('guardianPhone') ||
        values.containsKey('guardianEmail');
      if (current.guardianAccountId == null && guardianGiven) {
        if (!values.containsKey('guardianLastName')) {
          throw new AppException(
            'To add a guardian, tick (or type) the guardian\'s last name.'
          );
        }
        LearnerService.GuardianInput g = new LearnerService.GuardianInput();
        g.firstName = values.get('guardianFirstName');
        g.lastName = values.get('guardianLastName');
        g.email = values.get('guardianEmail');
        g.phone = values.get('guardianPhone');
        g.relationship = relationship(values.get('guardianRelationship'));
        g.isFeePayer = true;
        g.isEmergencyContact = true;
        g.portalAccess = false;
        LearnerService.addGuardian(app.AccountId, g);
        result.guardianAdded = true;
      } else if (current.guardianAccountId != null) {
        Account guardian = new Account(Id = current.guardianAccountId);
        if (values.containsKey('guardianEmail')) {
          guardian.put('PersonEmail', values.get('guardianEmail'));
          result.guardianFields++;
        }
        if (values.containsKey('guardianPhone')) {
          guardian.put('PersonMobilePhone', values.get('guardianPhone'));
          result.guardianFields++;
        }
        if (result.guardianFields > 0) {
          Database.update(guardian, AccessLevel.USER_MODE);
        }
      }
      List<String> details = new List<String>();
      if (values.containsKey('previousSchool')) {
        details.add('Previous school: ' + values.get('previousSchool'));
      }
      if (values.containsKey('previousGrade')) {
        details.add('Previous grade or class: ' + values.get('previousGrade'));
      }
      if (!details.isEmpty()) {
        String line =
          Date.today().format() +
          ' from ' +
          (String.isBlank(documentName)
            ? 'a document'
            : documentName.left(80)) +
          ': ' +
          String.join(details, '; ');
        String existing = app.Document_Details__c;
        new Writer()
          .updateApplication(
            new IndividualApplication(
              Id = app.Id,
              Document_Details__c = (String.isBlank(existing)
                  ? line
                  : existing + '\n' + line)
                .right(4000)
            )
          );
        result.detailsNoted = true;
      }
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
    if (interactionId != null) {
      // Only corrections count as edits: proposals left unticked are staff
      // decisions about conflicts, not mistakes by the reader.
      AiService.review(
        interactionId,
        'Accepted',
        corrected(interactionId, values),
        null,
        null
      );
      result.outcome = [
        SELECT Outcome__c
        FROM AI_Interaction__c
        WHERE Id = :interactionId
        WITH SYSTEM_MODE
      ]
      .Outcome__c;
    }
    Logger.info(
      'AiExtractionService',
      'Applied ' + values.size() + ' document details to ' + app.Id
    );
    return result;
  }

  // ---------------------------------------------------------------- helpers

  private class Current {
    Id guardianAccountId;
    Map<String, String> values = new Map<String, String>();
  }

  private static IndividualApplication application(Id applicationId) {
    List<IndividualApplication> rows = [
      SELECT Id, AccountId, Branch__c, Document_Details__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Application not found.');
    }
    if (rows[0].AccountId == null) {
      throw new AppException('The application has no applicant.');
    }
    return rows[0];
  }

  private static Current currentValues(IndividualApplication app) {
    Current c = new Current();
    Account a = [
      SELECT
        FirstName,
        LastName,
        PersonBirthdate,
        PersonEmail,
        PersonMobilePhone,
        PersonMailingStreet,
        PersonMailingCity,
        PersonMailingPostalCode,
        PersonContactId
      FROM Account
      WHERE Id = :app.AccountId
      WITH USER_MODE
    ];
    c.values.put('learnerFirstName', a.FirstName);
    c.values.put('learnerLastName', a.LastName);
    c.values.put(
      'dateOfBirth',
      a.PersonBirthdate == null ? null : String.valueOf(a.PersonBirthdate)
    );
    c.values.put('learnerEmail', a.PersonEmail);
    c.values.put('learnerPhone', a.PersonMobilePhone);
    c.values.put('street', a.PersonMailingStreet);
    c.values.put('city', a.PersonMailingCity);
    c.values.put('postalCode', a.PersonMailingPostalCode);
    if (a.PersonContactId != null) {
      Id roleId = GuardianRelationshipService.guardianRoleRelationId();
      for (ContactContactRelation rel : [
        SELECT
          Contact.AccountId,
          Contact.FirstName,
          Contact.LastName,
          Contact.Email,
          Contact.MobilePhone,
          Guardian_Relationship__c
        FROM ContactContactRelation
        WHERE
          RelatedContactId = :a.PersonContactId
          AND PartyRoleRelationId = :roleId
          AND IsActive = TRUE
        // USER_MODE with binds fails on this object (see GuardianRelationshipService).
        WITH SYSTEM_MODE
        ORDER BY Is_Fee_Payer__c DESC, CreatedDate
        LIMIT 1
      ]) {
        c.guardianAccountId = rel.Contact.AccountId;
        c.values.put('guardianFirstName', rel.Contact.FirstName);
        c.values.put('guardianLastName', rel.Contact.LastName);
        c.values.put('guardianRelationship', rel.Guardian_Relationship__c);
        c.values.put('guardianPhone', rel.Contact.MobilePhone);
        c.values.put('guardianEmail', rel.Contact.Email);
      }
    }
    return c;
  }

  private static String value(Map<String, Object> data, String key) {
    Object v = data == null ? null : data.get(key);
    if (v == null) {
      return null;
    }
    String s = String.valueOf(v).trim();
    return String.isBlank(s) || s.equalsIgnoreCase('null') ? null : s.left(255);
  }

  @TestVisible
  private static String normalise(String key, String value) {
    if (String.isBlank(value)) {
      return null;
    }
    if (key == 'learnerEmail' || key == 'guardianEmail') {
      return value.toLowerCase().deleteWhitespace();
    }
    if (key == 'learnerPhone' || key == 'guardianPhone') {
      return value.replaceAll('[^0-9+]', '');
    }
    if (key == 'dateOfBirth') {
      return toIsoDate(value);
    }
    return value;
  }

  /** YYYY-MM-DD from ISO or DD/MM/YYYY (Indian day-first) dates; else as given. */
  @TestVisible
  private static String toIsoDate(String value) {
    String v = value.trim();
    Matcher iso = Pattern.compile('^(\\d{4})-(\\d{1,2})-(\\d{1,2})$')
      .matcher(v);
    Matcher dmy = Pattern.compile('^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{4})$')
      .matcher(v);
    try {
      if (iso.matches()) {
        return String.valueOf(
          Date.newInstance(
            Integer.valueOf(iso.group(1)),
            Integer.valueOf(iso.group(2)),
            Integer.valueOf(iso.group(3))
          )
        );
      }
      if (dmy.matches()) {
        return String.valueOf(
          Date.newInstance(
            Integer.valueOf(dmy.group(3)),
            Integer.valueOf(dmy.group(2)),
            Integer.valueOf(dmy.group(1))
          )
        );
      }
    } catch (Exception e) {
      return v;
    }
    return v;
  }

  /** Both values present and different (ignoring case and spaces). */
  private static Boolean differentValue(String current, String proposed) {
    return String.isNotBlank(current) &&
      String.isNotBlank(proposed) &&
      !same(current, proposed);
  }

  private static Boolean isDate(String value) {
    return Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', value);
  }

  private static Boolean same(String a, String b) {
    return String.isNotBlank(a) &&
      String.isNotBlank(b) &&
      a.trim().equalsIgnoreCase(b.trim());
  }

  private static void validate(Map<String, String> values) {
    if (values.containsKey('dateOfBirth')) {
      String v = values.get('dateOfBirth');
      if (!isDate(v)) {
        throw new AppException('Date of birth must be a date (YYYY-MM-DD).');
      }
      Date d = Date.valueOf(v);
      if (d > Date.today() || d < Date.today().addYears(-100)) {
        throw new AppException('Date of birth ' + v + ' is not plausible.');
      }
    }
    for (String key : new List<String>{ 'learnerEmail', 'guardianEmail' }) {
      if (
        values.containsKey(key) &&
        !Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', values.get(key))
      ) {
        throw new AppException(values.get(key) + ' is not a valid email.');
      }
    }
    for (String key : new List<String>{ 'learnerPhone', 'guardianPhone' }) {
      if (
        values.containsKey(key) &&
        values.get(key).replaceAll('[^0-9]', '').length() < 7
      ) {
        throw new AppException(
          values.get(key) + ' is not a valid phone number.'
        );
      }
    }
  }

  private static String relationship(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String v = value.trim().toLowerCase();
    if (v.contains('father') || v == 'dad') {
      return 'Father';
    }
    if (v.contains('mother') || v == 'mum' || v == 'mom') {
      return 'Mother';
    }
    if (v.contains('grand')) {
      return 'Grandparent';
    }
    if (
      v.contains('brother') ||
      v.contains('sister') ||
      v.contains('sibling')
    ) {
      return 'Sibling';
    }
    if (v.contains('guardian')) {
      return 'Guardian';
    }
    return 'Other';
  }

  /**
   * The proposals as stored at extraction ("Label: value" lines) with the
   * applied values put in; values staff typed for fields the reader did
   * not propose are added at the end.
   */
  private static String corrected(
    Id interactionId,
    Map<String, String> values
  ) {
    List<AI_Interaction__c> rows = [
      SELECT Response__c
      FROM AI_Interaction__c
      WHERE Id = :interactionId
      WITH SYSTEM_MODE
    ];
    List<String> lines = rows.isEmpty() || rows[0].Response__c == null
      ? new List<String>()
      : rows[0].Response__c.split('\n');
    for (Def d : DEFS) {
      if (!values.containsKey(d.key)) {
        continue;
      }
      String line = d.label + ': ' + values.get(d.key);
      Boolean found = false;
      for (Integer i = 0; i < lines.size(); i++) {
        if (lines[i].startsWith(d.label + ': ')) {
          lines[i] = line;
          found = true;
          break;
        }
      }
      if (!found) {
        lines.add(line);
      }
    }
    return String.join(lines, '\n');
  }

  /** One "Label: value" line per proposal: the comparable form of a result. */
  private static String describe(List<Proposal> proposals) {
    List<String> lines = new List<String>();
    for (Proposal p : proposals) {
      lines.add(p.label + ': ' + p.proposed);
    }
    return String.join(lines, '\n');
  }

  private without sharing class Writer {
    void updateApplication(IndividualApplication app) {
      Database.update(app, AccessLevel.SYSTEM_MODE);
    }
  }
}
