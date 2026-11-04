/**
 * College admission catalogue shared by the admission desk and the public enquiry
 * page: open intakes with cut-offs, and what a branch and route need (marks,
 * stream, entrance exams, documents, fees). Published admission information
 * only, read in system mode; it never returns student data.
 */
public without sharing class CollegeAdmissionCatalog {
  public static List<CollegeAdmissionController.CampusChoice> catalogue() {
    Map<String, Admission_Rule__c> rules = new Map<String, Admission_Rule__c>();
    for (Admission_Rule__c rule : [
      SELECT
        Branch__c,
        Campus__c,
        Entry_Route__c,
        Academic_Year__c,
        Qualifying_Level__c,
        Qualifying_Streams__c,
        Min_Percentage__c,
        Entrance_Required__c
      FROM Admission_Rule__c
      WHERE Status__c = 'Active'
      WITH SYSTEM_MODE
    ]) {
      String key =
        rule.Branch__c +
        '|' +
        rule.Academic_Year__c +
        '|' +
        rule.Entry_Route__c;
      // A campus-specific rule is listed per campus below; the all-campus rule is the default.
      if (rule.Campus__c != null) {
        key += '|' + rule.Campus__c;
      }
      rules.put(key, rule);
    }
    Map<Id, CollegeAdmissionController.CampusChoice> campuses = new Map<Id, CollegeAdmissionController.CampusChoice>();
    Map<String, CollegeAdmissionController.ProgrammeChoice> programmes = new Map<String, CollegeAdmissionController.ProgrammeChoice>();
    for (Campus_Branch__c cb : [
      SELECT
        Id,
        Academic_Year__c,
        Campus__c,
        Campus__r.Name,
        Campus__r.Branch_Code__c,
        Branch__c,
        Branch__r.Name,
        Branch__r.Branch_Code__c,
        Branch__r.External_ID__c,
        Branch__r.Programme__c,
        Branch__r.Programme__r.Name,
        Branch__r.Programme__r.Programme_Code__c,
        Branch__r.Programme__r.Duration_Years__c,
        Intake_Regular__c,
        Intake_Lateral__c,
        Reserved_Regular__c,
        Reserved_Lateral__c,
        Finalised_Regular__c,
        Finalised_Lateral__c
      FROM Campus_Branch__c
      WHERE
        Admissions_Open__c = TRUE
        AND Campus__r.Institution_Type__c = 'College'
      WITH SYSTEM_MODE
      ORDER BY
        Campus__r.Name,
        Branch__r.Programme__r.Programme_Code__c DESC,
        Branch__r.Name
      LIMIT 500
    ]) {
      CollegeAdmissionController.CampusChoice campus = campuses.get(
        cb.Campus__c
      );
      if (campus == null) {
        campus = new CollegeAdmissionController.CampusChoice();
        campus.id = cb.Campus__c;
        campus.name = cb.Campus__r.Name;
        campus.academicYear = cb.Academic_Year__c;
        campus.code = cb.Campus__r.Branch_Code__c;
        campuses.put(cb.Campus__c, campus);
      }
      String programmeKey = cb.Campus__c + '|' + cb.Branch__r.Programme__c;
      CollegeAdmissionController.ProgrammeChoice programme = programmes.get(
        programmeKey
      );
      if (programme == null) {
        programme = new CollegeAdmissionController.ProgrammeChoice();
        programme.id = cb.Branch__r.Programme__c;
        programme.name = cb.Branch__r.Programme__r.Name;
        programme.code = cb.Branch__r.Programme__r.Programme_Code__c;
        programme.years = cb.Branch__r.Programme__r.Duration_Years__c;
        programmes.put(programmeKey, programme);
        campus.programmes.add(programme);
      }
      CollegeAdmissionController.BranchChoice branch = new CollegeAdmissionController.BranchChoice();
      branch.campusBranchId = cb.Id;
      branch.name = cb.Branch__r.Name;
      branch.code = cb.Branch__r.Branch_Code__c;
      branch.externalId = cb.Branch__r.External_ID__c;
      branch.seatsRegular =
        nvl(cb.Intake_Regular__c) -
        nvl(cb.Reserved_Regular__c) -
        nvl(cb.Finalised_Regular__c);
      branch.seatsLateral =
        nvl(cb.Intake_Lateral__c) -
        nvl(cb.Reserved_Lateral__c) -
        nvl(cb.Finalised_Lateral__c);
      String base = cb.Branch__c + '|' + cb.Academic_Year__c + '|';
      Admission_Rule__c regular = rules.containsKey(
          base + 'Regular|' + cb.Campus__c
        )
        ? rules.get(base + 'Regular|' + cb.Campus__c)
        : rules.get(base + 'Regular');
      if (regular != null) {
        branch.cutoff =
          regular.Qualifying_Level__c +
          (String.isBlank(regular.Qualifying_Streams__c)
            ? ''
            : ' ' + regular.Qualifying_Streams__c.replace(';', '/')) +
          ' ' +
          regular.Min_Percentage__c.setScale(0) +
          '%' +
          (regular.Entrance_Required__c ? ' + entrance rank' : '');
      }
      branch.lateral =
        (rules.containsKey(base + 'Lateral') ||
        rules.containsKey(base + 'Lateral|' + cb.Campus__c)) &&
        nvl(cb.Intake_Lateral__c) > 0;
      programme.branches.add(branch);
    }
    return campuses.values();
  }

  public static CollegeAdmissionController.Requirements requirements(
    Id campusBranchId,
    String entryRoute
  ) {
    CollegeAdmissionController.Requirements result = new CollegeAdmissionController.Requirements();
    Campus_Branch__c intake = [
      SELECT
        Id,
        Academic_Year__c,
        Campus__c,
        Branch__c,
        Branch__r.Programme__c,
        Intake_Regular__c,
        Intake_Lateral__c,
        Reserved_Regular__c,
        Reserved_Lateral__c,
        Finalised_Regular__c,
        Finalised_Lateral__c
      FROM Campus_Branch__c
      WHERE Id = :campusBranchId AND Campus__r.Institution_Type__c = 'College'
      WITH SYSTEM_MODE
    ];
    Boolean lateral = entryRoute == 'Lateral';
    result.seatsLeft = lateral
      ? nvl(intake.Intake_Lateral__c) -
        nvl(intake.Reserved_Lateral__c) -
        nvl(intake.Finalised_Lateral__c)
      : nvl(intake.Intake_Regular__c) -
        nvl(intake.Reserved_Regular__c) -
        nvl(intake.Finalised_Regular__c);
    Admission_Rule__c rule = AdmissionEligibilityService.activeRule(
      campusBranchId,
      entryRoute
    );
    if (rule == null) {
      result.message = 'Admissions are not open for this branch and route.';
      return result;
    }
    result.open = true;
    result.qualifyingLevel = rule.Qualifying_Level__c;
    result.minimum = rule.Min_Percentage__c;
    result.entryYear = lateral ? 2 : 1;
    if (String.isNotBlank(rule.Qualifying_Streams__c)) {
      result.streams = rule.Qualifying_Streams__c.split(';');
    }
    if (String.isNotBlank(rule.Qualifying_Branch_Codes__c)) {
      result.diplomaBranchCodes = rule.Qualifying_Branch_Codes__c.split(';');
    }
    result.entranceRequired = rule.Entrance_Required__c;
    for (Admission_Rule_Entrance__c e : rule.Accepted_Entrances__r) {
      CollegeAdmissionController.EntranceOption option = new CollegeAdmissionController.EntranceOption();
      option.exam = e.Entrance_Exam__c;
      option.maxRank = e.Max_Rank__c;
      result.entrances.add(option);
    }
    Integer year = lateral ? 2 : 1;
    for (Fee_Price__c price : [
      SELECT Fee_Type__c, Billing_Frequency__c, Amount__c
      FROM Fee_Price__c
      WHERE
        Learning_Course__c = :intake.Branch__c
        AND Active__c = TRUE
        AND (Branch__c = NULL
        OR Branch__c = :intake.Campus__c)
        AND (Academic_Year__c = NULL
        OR Academic_Year__c = :intake.Academic_Year__c)
        AND (Year_Of_Study__c = NULL
        OR Year_Of_Study__c = :year)
      WITH SYSTEM_MODE
    ]) {
      if (price.Fee_Type__c == 'Admission') {
        result.admissionFee = price.Amount__c;
      } else if (price.Billing_Frequency__c == 'Annual') {
        result.tuition = price.Amount__c;
      }
    }
    Set<String> levels = new Set<String>{ 'SSLC', rule.Qualifying_Level__c };
    for (Admission_Document_Rule__c d : [
      SELECT
        Label__c,
        Required__c,
        Sensitive_Class__c,
        Programme__c,
        Entry_Route__c,
        Qualifying_Level__c
      FROM Admission_Document_Rule__c
      WHERE Active__c = TRUE AND Academic_Year__c = :intake.Academic_Year__c
      WITH SYSTEM_MODE
      ORDER BY Sort_Order__c
    ]) {
      Boolean applies =
        (d.Programme__c == null ||
        d.Programme__c == intake.Branch__r.Programme__c) &&
        (String.isBlank(d.Entry_Route__c) || d.Entry_Route__c == entryRoute) &&
        (String.isBlank(d.Qualifying_Level__c) ||
        levels.contains(d.Qualifying_Level__c));
      if (applies) {
        CollegeAdmissionController.DocumentNeed need = new CollegeAdmissionController.DocumentNeed();
        need.label = d.Label__c;
        need.required = d.Required__c;
        need.sensitiveClass = d.Sensitive_Class__c;
        result.documents.add(need);
      }
    }
    return result;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
