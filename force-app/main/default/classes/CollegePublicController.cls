/**
 * Guest-safe boundary for the public college enquiry on /s/enquire.
 *
 * Returns published admission information only (open college intakes, cut-offs,
 * fees, documents) and runs the cut-off self-check on what the visitor typed.
 * Nothing is saved here and no student data is read; the enquiry itself is
 * submitted through PublicEnquiryController. Every input is validated again on
 * the server: the campus branch must be an open college intake, the route one
 * of the two entry routes, and marks and ranks within range.
 */
public without sharing class CollegePublicController {
  private static final Set<String> ROUTES = new Set<String>{
    'Regular',
    'Lateral'
  };
  private static final Set<String> LEVELS = new Set<String>{
    'SSLC',
    'PUC',
    'Diploma'
  };
  private static final Set<String> STREAMS = new Set<String>{
    'Science',
    'Commerce',
    'Arts'
  };
  private static final Set<String> EXAMS = new Set<String>{
    'KCET',
    'COMEDK',
    'DCET'
  };
  private static final Integer MAX_RANK = 2000000;

  public class QuotaOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Id value;
    @AuraEnabled
    public String rankExam;
  }

  /** Quotas of the intake that still have regular seats (none: no quota choice). */
  @AuraEnabled
  public static List<QuotaOption> getQuotas(Id campusBranchId) {
    try {
      assertIntake(campusBranchId, 'Regular');
      List<QuotaOption> result = new List<QuotaOption>();
      for (
        CollegeQuotaService.QuotaSeats q : CollegeQuotaService.openQuotas(
          campusBranchId
        )
      ) {
        QuotaOption o = new QuotaOption();
        o.label = q.name;
        o.value = q.quotaId;
        o.rankExam = q.rankExam;
        result.add(o);
      }
      return result;
    } catch (Exception e) {
      throw handled(e, 'Quotas are not available right now.');
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<CollegeAdmissionController.CampusChoice> getCatalogue() {
    try {
      List<CollegeAdmissionController.CampusChoice> campuses = CollegeAdmissionCatalog.catalogue();
      // Seat counts are internal: the public page shows only whether a route is offered.
      for (CollegeAdmissionController.CampusChoice campus : campuses) {
        for (
          CollegeAdmissionController.ProgrammeChoice programme : campus.programmes
        ) {
          for (
            CollegeAdmissionController.BranchChoice branch : programme.branches
          ) {
            branch.seatsRegular = null;
            branch.seatsLateral = null;
          }
        }
      }
      return campuses;
    } catch (Exception e) {
      throw handled(e, 'Programme information is not available right now.');
    }
  }

  @AuraEnabled(cacheable=true)
  public static CollegeAdmissionController.Requirements getRequirements(
    Id campusBranchId,
    String entryRoute
  ) {
    try {
      assertIntake(campusBranchId, entryRoute);
      CollegeAdmissionController.Requirements result = CollegeAdmissionCatalog.requirements(
        campusBranchId,
        entryRoute
      );
      result.seatsLeft = null;
      return result;
    } catch (Exception e) {
      throw handled(e, 'Programme information is not available right now.');
    }
  }

  /** Self-check against the published cut-off; nothing is saved. */
  @AuraEnabled
  public static AdmissionEligibilityService.Preview checkEligibility(
    Id campusBranchId,
    String entryRoute,
    List<CollegeAdmissionController.Qualification> qualifications,
    List<CollegeAdmissionController.Entrance> entrances
  ) {
    try {
      validateDeclaration(
        campusBranchId,
        entryRoute,
        qualifications,
        entrances
      );
      return CollegeAdmissionController.previewEligibility(
        campusBranchId,
        entryRoute,
        qualifications == null
          ? new List<CollegeAdmissionController.Qualification>()
          : qualifications,
        entrances == null
          ? new List<CollegeAdmissionController.Entrance>()
          : entrances
      );
    } catch (Exception e) {
      throw handled(e, 'The eligibility check is not available right now.');
    }
  }

  /**
   * Validates what a visitor declared: an open college intake, a valid route,
   * and marks and ranks within range. Shared with the enquiry submission so the
   * stored declaration obeys the same rules as the self-check.
   */
  public static void validateDeclaration(
    Id campusBranchId,
    String entryRoute,
    List<CollegeAdmissionController.Qualification> qualifications,
    List<CollegeAdmissionController.Entrance> entrances
  ) {
    assertIntake(campusBranchId, entryRoute);
    validateMarks(qualifications, entrances);
  }

  /** Marks and ranks: known levels and exams, each once, in range, sensible years. */
  public static void validateMarks(
    List<CollegeAdmissionController.Qualification> qualifications,
    List<CollegeAdmissionController.Entrance> entrances
  ) {
    List<CollegeAdmissionController.Qualification> declared = qualifications ==
      null
      ? new List<CollegeAdmissionController.Qualification>()
      : qualifications;
    List<CollegeAdmissionController.Entrance> ranks = entrances == null
      ? new List<CollegeAdmissionController.Entrance>()
      : entrances;
    if (declared.size() > 3 || ranks.size() > 2) {
      throw new AppException(
        'Enter at most three results and two entrance ranks.'
      );
    }
    Set<String> levelsSeen = new Set<String>();
    for (CollegeAdmissionController.Qualification q : declared) {
      if (q != null && !levelsSeen.add(String.valueOf(q.level))) {
        throw new AppException('Enter each result (SSLC, PUC, Diploma) once.');
      }
      if (q != null && !InputValidator.isResultYear(q.year)) {
        throw new AppException(
          'The year of a result must be between ' +
            InputValidator.EARLIEST_RESULT_YEAR +
            ' and this year.'
        );
      }
      if (
        q == null ||
        !LEVELS.contains(q.level) ||
        !InputValidator.isPercentage(q.percentage) ||
        (String.isNotBlank(q.stream) && !STREAMS.contains(q.stream)) ||
        (String.isNotBlank(q.branchCode) &&
        !Pattern.matches('^[A-Za-z]{2}$', q.branchCode))
      ) {
        throw new AppException(
          'Check the marks you entered: each percentage is from 0 to 100 with at most two decimals.'
        );
      }
    }
    Set<String> examsSeen = new Set<String>();
    for (CollegeAdmissionController.Entrance e : ranks) {
      if (e != null && !examsSeen.add(String.valueOf(e.exam))) {
        throw new AppException('Enter each entrance exam once.');
      }
      if (e != null && !InputValidator.isResultYear(e.year)) {
        throw new AppException(
          'The entrance exam year must be between ' +
            InputValidator.EARLIEST_RESULT_YEAR +
            ' and this year.'
        );
      }
      if (
        e == null ||
        !EXAMS.contains(e.exam) ||
        e.rank == null ||
        e.rank < 1 ||
        e.rank > MAX_RANK
      ) {
        throw new AppException('Check the entrance exam and rank you entered.');
      }
    }
  }

  private static void assertIntake(Id campusBranchId, String entryRoute) {
    if (campusBranchId == null || !ROUTES.contains(entryRoute)) {
      throw new AppException('Choose a programme and entry route.');
    }
    Integer open = [
      SELECT COUNT()
      FROM Campus_Branch__c
      WHERE
        Id = :campusBranchId
        AND Admissions_Open__c = TRUE
        AND Campus__r.Institution_Type__c = 'College'
      WITH SYSTEM_MODE
    ];
    if (open == 0) {
      throw new AppException('Admissions are not open for this programme.');
    }
  }

  private static AuraHandledException handled(Exception e, String fallback) {
    String message = e instanceof AppException ? e.getMessage() : fallback;
    if (!(e instanceof AppException)) {
      Logger.error('CollegePublicController', e, null);
    }
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
