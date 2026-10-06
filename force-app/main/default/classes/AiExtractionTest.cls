@IsTest
private class AiExtractionTest {
  private class StubProvider implements AiService.Provider {
    String answer;
    String lastMessage;
    StubProvider(String answer) {
      this.answer = answer;
    }
    public String complete(String model, String instructions, String message) {
      lastMessage = message;
      return answer;
    }
  }

  private static final String BIRTH_CERTIFICATE =
    '```json\n{"documentType": "Birth Certificate", "learnerFirstName": "Ananya", "learnerLastName": "Docreader", ' +
    '"dateOfBirth": "15/03/2014", "learnerEmail": null, "learnerPhone": "+91 98450 11111", "street": "12 MG Road", "city": "Bengaluru", ' +
    '"postalCode": "560001", "guardianFirstName": "Suresh", "guardianLastName": "Docreader", "guardianRelationship": "father", ' +
    '"guardianPhone": "+91 98450 22222", "guardianEmail": "Suresh.D@Example.com", "previousSchool": "Delhi Public School", "previousGrade": "V"}\n```';

  private static final String DOCUMENT_TEXT = 'GOVERNMENT OF KARNATAKA - BIRTH CERTIFICATE. Name of child: Ananya Docreader. Date of birth: 15/03/2014.';

  private static User aiUser() {
    User u = TestDataFactory.admin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.assignPermissionSets(
        u.Id,
        new List<String>{ 'KEM_AI_User' }
      );
    }
    // Applications are private: hand the test application to this user.
    IndividualApplication app = application();
    update new IndividualApplication(Id = app.Id, OwnerId = u.Id);
    update new Account(Id = app.AccountId, OwnerId = u.Id);
    return u;
  }

  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      insert branch;
      Account learner = PersonAccountService.buildPerson(
        'Ananya',
        'Docreader',
        null,
        null,
        branch.Id,
        'Learner'
      );
      learner.PersonMailingCity = 'Mysuru';
      insert learner;
      learner = [
        SELECT Id, PersonContactId
        FROM Account
        WHERE Id = :learner.Id
      ];
      insert new IndividualApplication(
        Category = 'Education',
        AccountId = learner.Id,
        ContactId = learner.PersonContactId,
        Status = 'Processing',
        Branch__c = branch.Id
      );
    }
  }

  private static IndividualApplication application() {
    return [
      SELECT Id, AccountId
      FROM IndividualApplication
      WHERE Account.LastName = 'Docreader'
      LIMIT 1
    ];
  }

  private static Map<String, AiExtractionService.Proposal> byKey(
    AiExtractionService.Extraction e
  ) {
    Map<String, AiExtractionService.Proposal> result = new Map<String, AiExtractionService.Proposal>();
    for (AiExtractionService.Proposal p : e.proposals) {
      result.put(p.key, p);
    }
    return result;
  }

  private static AiExtractionService.Change change(String key, String value) {
    AiExtractionService.Change c = new AiExtractionService.Change();
    c.key = key;
    c.value = value;
    return c;
  }

  @IsTest
  static void proposesDetailsNextToCurrentValues() {
    StubProvider stub = new StubProvider(BIRTH_CERTIFICATE);
    AiService.testProvider = stub;
    IndividualApplication app = application();
    System.runAs(aiUser()) {
      AiExtractionService.Extraction e = AiController.extractDocument(
        app.Id,
        'Birth certificate.pdf',
        DOCUMENT_TEXT
      );
      Assert.areEqual('Birth Certificate', e.documentType, 'Type');
      Assert.areEqual(14, e.found, 'Fields found (email null)');
      Assert.isFalse(e.hasGuardian, 'No guardian yet');
      Assert.isTrue(stub.lastMessage.contains('Name of child'), 'Text sent');
      Map<String, AiExtractionService.Proposal> p = byKey(e);
      Assert.areEqual('2014-03-15', p.get('dateOfBirth').proposed, 'ISO date');
      Assert.isTrue(p.get('dateOfBirth').selected, 'Blank filled by default');
      Assert.isFalse(p.get('learnerLastName').differs, 'Same name');
      Assert.isFalse(p.get('learnerLastName').selected, 'Same not ticked');
      Assert.isTrue(p.get('city').differs, 'City differs');
      Assert.isFalse(p.get('city').selected, 'Conflicts are not pre-ticked');
      Assert.isNotNull(p.get('city').note, 'Conflict explained');
      Assert.areEqual('+919845011111', p.get('learnerPhone').proposed, 'Phone');
      Assert.areEqual(
        'suresh.d@example.com',
        p.get('guardianEmail').proposed,
        'Email'
      );
      Assert.isFalse(p.containsKey('learnerEmail'), 'Null values skipped');
      AI_Interaction__c row = [
        SELECT Feature__c, Response__c, Outcome__c, Record_Id__c
        FROM AI_Interaction__c
        WHERE Id = :e.interactionId
      ];
      Assert.areEqual('Document Extraction', row.Feature__c, 'Feature');
      Assert.isTrue(
        row.Response__c.contains('Date of birth: 2014-03-15'),
        'Comparable form stored'
      );
      Assert.areEqual('Pending Review', row.Outcome__c, 'Awaiting review');
    }
  }

  @IsTest
  static void appliesConfirmedDetailsAndAddsGuardian() {
    AiService.testProvider = new StubProvider(BIRTH_CERTIFICATE);
    IndividualApplication app = application();
    System.runAs(aiUser()) {
      AiExtractionService.Extraction e = AiExtractionService.extract(
        app.Id,
        'Birth certificate.pdf',
        DOCUMENT_TEXT
      );
      Test.startTest();
      AiExtractionService.ApplyResult result = AiController.applyExtraction(
        app.Id,
        e.interactionId,
        'Birth certificate.pdf',
        new List<AiExtractionService.Change>{
          change('dateOfBirth', '2014-03-15'),
          change('learnerPhone', '+919845011111'),
          change('city', 'Bengaluru'),
          change('guardianFirstName', 'Suresh'),
          change('guardianLastName', 'Docreader'),
          change('guardianRelationship', 'father'),
          change('guardianPhone', '+919845022222'),
          change('previousSchool', 'Delhi Public School'),
          change('unknownKey', 'ignored')
        }
      );
      Test.stopTest();
      Assert.areEqual(3, result.learnerFields, 'Learner fields');
      Assert.isTrue(result.guardianAdded, 'Guardian added');
      Assert.isTrue(result.detailsNoted, 'School noted');
      Assert.areEqual(
        'Accepted',
        result.outcome,
        'Values applied as read; unticked conflicts are not edits'
      );
    }
    Account learner = [
      SELECT
        PersonBirthdate,
        PersonMobilePhone,
        PersonMailingCity,
        PersonContactId
      FROM Account
      WHERE Id = :app.AccountId
    ];
    Assert.areEqual(
      Date.newInstance(2014, 3, 15),
      learner.PersonBirthdate,
      'DOB'
    );
    Assert.areEqual('Bengaluru', learner.PersonMailingCity, 'City replaced');
    ContactContactRelation rel = [
      SELECT Contact.LastName, Guardian_Relationship__c, Is_Fee_Payer__c
      FROM ContactContactRelation
      WHERE RelatedContactId = :learner.PersonContactId
    ];
    Assert.areEqual('Docreader', rel.Contact.LastName, 'Guardian');
    Assert.areEqual('Father', rel.Guardian_Relationship__c, 'Relationship');
    Assert.isTrue(rel.Is_Fee_Payer__c, 'Fee payer');
    String details = [
      SELECT Document_Details__c
      FROM IndividualApplication
      WHERE Id = :app.Id
    ]
    .Document_Details__c;
    Assert.isTrue(
      details.contains('Previous school: Delhi Public School') &&
      details.contains('Birth certificate.pdf'),
      details
    );
  }

  @IsTest
  static void existingGuardianKeepsNameAndGetsContactUpdates() {
    IndividualApplication app = application();
    System.runAs(TestDataFactory.admin()) {
      LearnerService.GuardianInput g = new LearnerService.GuardianInput();
      g.firstName = 'Lakshmi';
      g.lastName = 'Docreader';
      g.relationship = 'Mother';
      g.isFeePayer = true;
      LearnerService.addGuardian(app.AccountId, g);
    }
    AiService.testProvider = new StubProvider(BIRTH_CERTIFICATE);
    System.runAs(aiUser()) {
      AiExtractionService.Extraction e = AiExtractionService.extract(
        app.Id,
        'Birth certificate.pdf',
        DOCUMENT_TEXT
      );
      Assert.isTrue(e.hasGuardian, 'Guardian linked');
      Map<String, AiExtractionService.Proposal> p = byKey(e);
      Assert.isFalse(p.get('guardianFirstName').selectable, 'Name locked');
      Assert.isTrue(
        p.get('guardianFirstName').note.contains('different parent'),
        'Explained'
      );
      Assert.isFalse(
        p.get('guardianPhone').selectable,
        'Document names Suresh (father), linked guardian is Lakshmi (mother)'
      );
      Assert.isTrue(
        p.get('guardianPhone').note.contains('different parent'),
        p.get('guardianPhone').note
      );
      // A document naming the linked guardian may update their contact details.
      AiService.testProvider = new StubProvider(
        BIRTH_CERTIFICATE.replace('"Suresh"', '"Lakshmi"')
          .replace('"father"', '"Mother"')
      );
      p = byKey(
        AiExtractionService.extract(app.Id, 'Letter.pdf', DOCUMENT_TEXT)
      );
      Assert.isTrue(p.get('guardianPhone').selectable, 'Same person');
      Assert.isFalse(p.get('guardianFirstName').differs, 'Same first name');
      AiExtractionService.ApplyResult result = AiExtractionService.apply(
        app.Id,
        e.interactionId,
        'Birth certificate.pdf',
        new List<AiExtractionService.Change>{
          change('guardianPhone', '+919845022222'),
          change('guardianEmail', 'suresh.rao@example.com')
        }
      );
      Assert.isFalse(result.guardianAdded, 'No new guardian');
      Assert.areEqual('Edited', result.outcome, 'Corrected email = edited');
      Assert.areEqual(2, result.guardianFields, 'Guardian updated');
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Account
        WHERE PersonMobilePhone = '+919845022222' AND FirstName = 'Lakshmi'
      ],
      'Existing guardian updated'
    );
  }

  @IsTest
  static void validationAndFailures() {
    IndividualApplication app = application();
    System.runAs(aiUser()) {
      List<List<AiExtractionService.Change>> bad = new List<List<AiExtractionService.Change>>{
        new List<AiExtractionService.Change>(),
        new List<AiExtractionService.Change>{
          change('dateOfBirth', '15 March')
        },
        new List<AiExtractionService.Change>{
          change('dateOfBirth', String.valueOf(Date.today().addDays(5)))
        },
        new List<AiExtractionService.Change>{
          change('learnerEmail', 'not-an-email')
        },
        new List<AiExtractionService.Change>{ change('learnerPhone', '12') },
        new List<AiExtractionService.Change>{
          change('guardianPhone', '+919845022222')
        }
      };
      List<String> expected = new List<String>{
        'Tick at least one',
        'must be a date',
        'not plausible',
        'not a valid email',
        'not a valid phone',
        'guardian\'s last name'
      };
      for (Integer i = 0; i < bad.size(); i++) {
        try {
          AiExtractionService.apply(app.Id, null, null, bad[i]);
          Assert.fail('Expected failure ' + i);
        } catch (AppException e) {
          Assert.isTrue(e.getMessage().contains(expected[i]), e.getMessage());
        }
      }
      try {
        AiExtractionService.extract(app.Id, 'scan.pdf', '   ');
        Assert.fail('No text');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('no readable text'),
          e.getMessage()
        );
      }
      AiService.testProvider = new StubProvider('Sorry, I cannot help.');
      try {
        AiExtractionService.extract(app.Id, 'form.txt', DOCUMENT_TEXT);
        Assert.fail('Not JSON');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('usable details'),
          e.getMessage()
        );
      }
      try {
        AiController.extractDocument(null, 'x', DOCUMENT_TEXT);
        Assert.fail('No application');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('not found'), e.getMessage());
      }
    }
    Assert.areEqual(
      null,
      [SELECT PersonBirthdate FROM Account WHERE Id = :app.AccountId]
      .PersonBirthdate,
      'Nothing saved on failure'
    );
  }

  @IsTest
  static void attachedDocumentsAndContent() {
    IndividualApplication app = application();
    System.runAs(aiUser()) {
      List<ContentVersion> versions = new List<ContentVersion>{
        new ContentVersion(
          Title = 'Application form',
          PathOnClient = 'form.txt',
          VersionData = Blob.valueOf('Learner name: Ananya Docreader')
        ),
        new ContentVersion(
          Title = 'Birth certificate',
          PathOnClient = 'birth.pdf',
          VersionData = Blob.valueOf('%PDF-1.4 test')
        ),
        new ContentVersion(
          Title = 'Photo',
          PathOnClient = 'photo.jpg',
          VersionData = Blob.valueOf('jpeg')
        )
      };
      insert versions;
      List<ContentDocumentLink> links = new List<ContentDocumentLink>();
      for (ContentVersion v : [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id IN :versions
      ]) {
        links.add(
          new ContentDocumentLink(
            ContentDocumentId = v.ContentDocumentId,
            LinkedEntityId = app.Id,
            ShareType = 'V'
          )
        );
      }
      insert links;
      Map<String, AiExtractionService.Document> docs = new Map<String, AiExtractionService.Document>();
      for (
        AiExtractionService.Document d : AiController.applicationDocuments(
          app.Id
        )
      ) {
        docs.put(d.title, d);
      }
      Assert.areEqual(3, docs.size(), 'All files listed');
      Assert.isTrue(docs.get('Application form').readable, 'Text readable');
      Assert.isTrue(docs.get('Birth certificate').readable, 'PDF readable');
      Assert.isFalse(docs.get('Photo').readable, 'Image not readable');
      Assert.areEqual('Application', docs.get('Photo').attachedTo, 'Parent');

      AiExtractionService.FileContent text = AiController.documentContent(
        docs.get('Application form').contentVersionId
      );
      Assert.areEqual('text', text.kind, 'Text kind');
      Assert.isTrue(text.text.contains('Ananya'), 'Text returned');
      AiExtractionService.FileContent pdf = AiController.documentContent(
        docs.get('Birth certificate').contentVersionId
      );
      Assert.areEqual('pdf', pdf.kind, 'PDF kind');
      Assert.areEqual(
        Blob.valueOf('%PDF-1.4 test'),
        EncodingUtil.base64Decode(pdf.base64),
        'Bytes for the browser'
      );
      try {
        AiController.documentContent(docs.get('Photo').contentVersionId);
        Assert.fail('Image');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('OCR'), e.getMessage());
      }
    }
  }

  @IsTest
  static void dateAndValueNormalisation() {
    Assert.areEqual(
      '2014-03-05',
      AiExtractionService.toIsoDate('5/3/2014'),
      'DMY'
    );
    Assert.areEqual(
      '2014-03-05',
      AiExtractionService.toIsoDate('05.03.2014'),
      'Dots'
    );
    Assert.areEqual(
      '2014-03-05',
      AiExtractionService.toIsoDate('2014-3-5'),
      'ISO'
    );
    Assert.areEqual(
      'March 2014',
      AiExtractionService.toIsoDate('March 2014'),
      'Kept'
    );
    Assert.isNull(AiExtractionService.normalise('city', ' '), 'Blank');
    Assert.areEqual(
      '+91984',
      AiExtractionService.normalise('guardianPhone', '+91 (984)'),
      'Phone digits'
    );
  }
}
