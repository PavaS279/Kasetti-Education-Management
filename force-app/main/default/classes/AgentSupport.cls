/**
 * Shared helpers for the Agentforce actions (Agent*.cls).
 *
 * Agents pass either a record Id or a name typed in the conversation;
 * resolve() turns that into one record the user can see, or a readable
 * message asking the user to choose. Every action runs as the user, so
 * sharing, field access and the KEM Use AI permission all apply, and AI
 * calls are logged on the Agentforce channel.
 */
public with sharing class AgentSupport {
  public class ResolveException extends Exception {
  }

  /** Runs AI calls for an action on the Agentforce channel. */
  public static void begin() {
    AiService.channel = AiService.CHANNEL_AGENT;
  }

  /**
   * Finds one record of the given object by Id or (part of) its name.
   * extraFilter is appended to the WHERE clause (no user input).
   */
  public static SObject resolve(
    String objectName,
    String idOrName,
    String extraFilter,
    String noun
  ) {
    if (String.isBlank(idOrName)) {
      throw new ResolveException('Which ' + noun + '? Please give a name.');
    }
    String value = idOrName.trim();
    String condition = '';
    Map<String, Object> binds = new Map<String, Object>();
    if (isId(value)) {
      condition = 'Id = :value';
      binds.put('value', value);
    } else {
      condition = 'Name LIKE :pattern';
      binds.put('pattern', '%' + escapeLike(value) + '%');
    }
    if (String.isNotBlank(extraFilter)) {
      condition += ' AND ' + extraFilter;
    }
    List<SObject> rows = Database.queryWithBinds(
      'SELECT Id, Name FROM ' +
        objectName +
        ' WHERE ' +
        condition +
        ' ORDER BY Name LIMIT 6',
      binds,
      AccessLevel.USER_MODE
    );
    if (rows.isEmpty()) {
      throw new ResolveException(
        'I could not find a ' +
          noun +
          ' matching "' +
          value.left(80) +
          '" that you can see.'
      );
    }
    if (rows.size() > 1) {
      // An exact name match wins over partial matches.
      for (SObject row : rows) {
        if (((String) row.get('Name')).equalsIgnoreCase(value)) {
          return row;
        }
      }
      List<String> names = new List<String>();
      for (SObject row : rows) {
        names.add((String) row.get('Name'));
      }
      throw new ResolveException(
        'Several ' +
          noun +
          's match "' +
          value.left(80) +
          '": ' +
          String.join(names, '; ') +
          (rows.size() == 6 ? '; …' : '') +
          '. Which one?'
      );
    }
    return rows[0];
  }

  private static Boolean isId(String value) {
    if (value.length() != 15 && value.length() != 18) {
      return false;
    }
    try {
      Id.valueOf(value);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  private static String escapeLike(String value) {
    return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }

  /** A short, user-safe error for the agent to relay. */
  public static String failure(Exception e) {
    if (e instanceof ResolveException || e instanceof AppException) {
      return e.getMessage();
    }
    if (e instanceof QueryException || e instanceof NoAccessException) {
      return 'You do not have access to that information.';
    }
    Logger.error('AgentSupport', e, null);
    return 'Something went wrong: ' + e.getMessage().left(150);
  }
}
