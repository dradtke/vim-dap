import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import org.junit.Ignore;
import org.junit.runner.Description;
import org.junit.runner.JUnitCore;
import org.junit.runner.Request;
import org.junit.runner.Result;
import org.junit.runner.notification.RunListener;
import org.junit.runner.notification.Failure;

public class JUnit4TestRunner {
  public static void main(String... args) throws ClassNotFoundException {
    String[] classAndMethod = args[0].split("#");
    String classFilepath = args[1];
    String quickfixFile = args[2];
    Request request = classAndMethod.length > 1
      ? Request.method(Class.forName(classAndMethod[0]), classAndMethod[1])
      : Request.aClass(Class.forName(classAndMethod[0]));
    JUnitCore core = new JUnitCore();
    core.addListener(new Listener(classAndMethod[0], classFilepath, quickfixFile));
    Result result = core.run(request);
    System.exit(result.wasSuccessful() ? 0 : 1);
  }

  static class Listener extends RunListener {
    private final String className;
    private final String classFilepath;
    private final String quickfixFile;
    private final List<String> quickfixes;
    private Instant startTime;

    Listener(String className, String classFilepath, String quickfixFile) {
      this.className = className;
      this.classFilepath = classFilepath;
      this.quickfixFile = quickfixFile;
      this.quickfixes = new ArrayList<>();
    }

    public void testRunStarted(Description description) {
      startTime = Instant.now();
      final String className = description.getTestClass().getSimpleName();
      if (description.testCount() == 1) {
        System.out.println("==== Running 1 test in " + className + "... ====");
      } else {
        System.out.println("==== Running " + description.testCount() + " tests in " + className + "... ====");
      }
    }

    public void testStarted(Description description) {
      System.out.println("> running " + name(description));
    }

    public void testFailure(Failure failure) {
      System.out.println("    failure: " + failure.getMessage());
      for (StackTraceElement el : failure.getException().getStackTrace()) {
        if (el.getClassName().equals(this.className)) {
          quickfixes.add(String.format("%s:%s - %s", this.classFilepath, el.getLineNumber(), failure.getMessage().replace("\n", " ")));
          break;
        }
      }
    }

    public void testIgnored(Description description) {
      System.out.println("| ignoring " + name(description) + reason(description));
    }

    public void testRunFinished(Result result) {
      final Duration elapsed = Duration.between(startTime, Instant.now());
      System.out.println();
      for (Failure failure : result.getFailures()) {
        System.out.println("!!! " + name(failure.getDescription()));
        for (StackTraceElement el : failure.getException().getStackTrace()) {
          if (showStackTraceElement(el)) {
            System.out.println("\t" + el.toString());
          }
        }
        System.out.println();
      }
      String testOrTests = result.getRunCount() == 1 ? "test" : "tests";
      String failureOrFailures = result.getFailureCount() == 1 ? "failure" : "failures";
      System.out.println("==== " + result.getRunCount() + " " + testOrTests + " run, " + result.getFailureCount() + " " + failureOrFailures + " in " + getReadableDuration(elapsed) + " ====");

      if (!quickfixes.isEmpty()) {
        try {
          Files.write(Paths.get(quickfixFile), quickfixes);
        } catch (IOException e) {
          System.out.println();
          System.out.println("Failed to write quickfix file " + quickfixFile + ": " + e.getMessage());
        }
      }
    }

    private boolean showStackTraceElement(StackTraceElement el) {
      if (el.isNativeMethod()) {
        return false;
      }
      String className = el.getClassName();
      if (className.startsWith("org.junit.") || className.startsWith("sun.reflect.") || className.startsWith("java.lang.reflect.")) {
        return false;
      }
      if (className.equals("JUnit4TestRunner")) {
        return false;
      }
      return true;
    }

    private String getReadableDuration(Duration duration) {
      StringBuilder builder = new StringBuilder();
      if (duration.toHours() > 0) {
        builder.append(duration.toHours());
        builder.append(" hour" + (duration.toHours() != 1 ? "s" : "") + ", ");
        duration = duration.minusHours(duration.toHours());
      }
      if (duration.toMinutes() > 0) {
        builder.append(duration.toMinutes());
        builder.append(" minute" + (duration.toMinutes() != 1 ? "s" : "") + ", ");
        duration = duration.minusMinutes(duration.toMinutes());
      }
      builder.append(duration.getSeconds());
      builder.append(" second" + (duration.getSeconds() != 1 ? "s" : ""));
      duration = duration.minusSeconds(duration.getSeconds());
      return builder.toString();
    }

    private String name(Description description) {
      String name = description.getDisplayName();
      return description.isTest()
        ? name.substring(0, name.indexOf("("))
        : name;
    }

    private String reason(Description description) {
      Ignore annotation = description.getAnnotation(Ignore.class);
      if (annotation == null || annotation.value() == null) {
        return "";
      }
      return " (" + annotation.value() + ")";
    }
  }
}
