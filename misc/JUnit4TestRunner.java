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
  public static final boolean SUPPORTS_COLOR = System.console() != null && System.getenv("TERM") != null && !System.getenv("TERM").equals("dumb");

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
      Color.BLUE_BRIGHT.print();
      System.out.println("> running " + name(description));
      Color.RESET.print();
    }

    public void testFailure(Failure failure) {
      Color.RED_BRIGHT.print();
      System.out.println(failure.getMessage());
      boolean quickfixAdded = false;
      for (StackTraceElement el : failure.getException().getStackTrace()) {
        if (showStackTraceElement(el)) {
          System.out.println("\t" + el.toString());
        }
        if (!quickfixAdded && el.getClassName().equals(this.className)) {
          quickfixes.add(String.format("%s:%s - %s", this.classFilepath, el.getLineNumber(), failure.getMessage().replace("\n", " ")));
          quickfixAdded = true;
        }
      }
      Color.RESET.print();
    }

    public void testIgnored(Description description) {
      Color.BLUE.print();
      System.out.println("| ignoring " + name(description) + reason(description));
      Color.RESET.print();
    }

    public void testRunFinished(Result result) {
      final Duration elapsed = Duration.between(startTime, Instant.now());
      System.out.println();
      String testOrTests = result.getRunCount() == 1 ? "test" : "tests";
      String failureOrFailures = result.getFailureCount() == 1 ? "failure" : "failures";
      if (result.getFailureCount() == 0) {
        Color.GREEN_BRIGHT.print();
      } else {
        Color.RED_BRIGHT.print();
      }

      System.out.println("==== " + result.getRunCount() + " " + testOrTests + " run, " + result.getFailureCount() + " " + failureOrFailures + " in " + getReadableDuration(elapsed) + " ====");

      Color.RESET.print();

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

  // Borrowed from https://stackoverflow.com/a/51944613

  enum Color {
    //Color end string, color reset
    RESET("\033[0m"),

    // Regular Colors. Normal color, no bold, background color etc.
    BLACK("\033[0;30m"),
    RED("\033[0;31m"),
    GREEN("\033[0;32m"),
    YELLOW("\033[0;33m"),
    BLUE("\033[0;34m"),
    MAGENTA("\033[0;35m"),
    CYAN("\033[0;36m"),
    WHITE("\033[0;37m"),

    // Bold
    BLACK_BOLD("\033[1;30m"),
    RED_BOLD("\033[1;31m"),
    GREEN_BOLD("\033[1;32m"),
    YELLOW_BOLD("\033[1;33m"),
    BLUE_BOLD("\033[1;34m"),
    MAGENTA_BOLD("\033[1;35m"),
    CYAN_BOLD("\033[1;36m"),
    WHITE_BOLD("\033[1;37m"),

    // Underline
    BLACK_UNDERLINED("\033[4;30m"),
    RED_UNDERLINED("\033[4;31m"),
    GREEN_UNDERLINED("\033[4;32m"),
    YELLOW_UNDERLINED("\033[4;33m"),
    BLUE_UNDERLINED("\033[4;34m"),
    MAGENTA_UNDERLINED("\033[4;35m"),
    CYAN_UNDERLINED("\033[4;36m"),
    WHITE_UNDERLINED("\033[4;37m"),

    // Background
    BLACK_BACKGROUND("\033[40m"),
    RED_BACKGROUND("\033[41m"),
    GREEN_BACKGROUND("\033[42m"),
    YELLOW_BACKGROUND("\033[43m"),
    BLUE_BACKGROUND("\033[44m"),
    MAGENTA_BACKGROUND("\033[45m"),
    CYAN_BACKGROUND("\033[46m"),
    WHITE_BACKGROUND("\033[47m"),

    // High Intensity
    BLACK_BRIGHT("\033[0;90m"),
    RED_BRIGHT("\033[0;91m"),
    GREEN_BRIGHT("\033[0;92m"),
    YELLOW_BRIGHT("\033[0;93m"),
    BLUE_BRIGHT("\033[0;94m"),
    MAGENTA_BRIGHT("\033[0;95m"),
    CYAN_BRIGHT("\033[0;96m"),
    WHITE_BRIGHT("\033[0;97m"),

    // Bold High Intensity
    BLACK_BOLD_BRIGHT("\033[1;90m"),
    RED_BOLD_BRIGHT("\033[1;91m"),
    GREEN_BOLD_BRIGHT("\033[1;92m"),
    YELLOW_BOLD_BRIGHT("\033[1;93m"),
    BLUE_BOLD_BRIGHT("\033[1;94m"),
    MAGENTA_BOLD_BRIGHT("\033[1;95m"),
    CYAN_BOLD_BRIGHT("\033[1;96m"),
    WHITE_BOLD_BRIGHT("\033[1;97m"),

    // High Intensity backgrounds
    BLACK_BACKGROUND_BRIGHT("\033[0;100m"),
    RED_BACKGROUND_BRIGHT("\033[0;101m"),
    GREEN_BACKGROUND_BRIGHT("\033[0;102m"),
    YELLOW_BACKGROUND_BRIGHT("\033[0;103m"),
    BLUE_BACKGROUND_BRIGHT("\033[0;104m"),
    MAGENTA_BACKGROUND_BRIGHT("\033[0;105m"),
    CYAN_BACKGROUND_BRIGHT("\033[0;106m"),
    WHITE_BACKGROUND_BRIGHT("\033[0;107m");

    private final String code;

    Color(String code) {
      this.code = code;
    }

    public void print() {
      if (SUPPORTS_COLOR) {
        System.out.print(this.code);
      }
    }
  }
}
