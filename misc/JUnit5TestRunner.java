import java.io.PrintWriter;
import java.util.List;
import java.util.ArrayList;

import org.junit.platform.engine.DiscoverySelector;
import org.junit.platform.engine.discovery.DiscoverySelectors;
import org.junit.platform.engine.support.descriptor.ClassSource;
import org.junit.platform.launcher.Launcher;
import org.junit.platform.launcher.LauncherDiscoveryRequest;
import org.junit.platform.launcher.TestPlan;
import org.junit.platform.launcher.core.LauncherDiscoveryRequestBuilder;
import org.junit.platform.launcher.core.LauncherFactory;
import org.junit.platform.launcher.listeners.SummaryGeneratingListener;
import org.junit.platform.launcher.listeners.TestExecutionSummary;

// From https://www.baeldung.com/junit-tests-run-programmatically-from-java
public class JUnit5TestRunner {
  public static final boolean SUPPORTS_COLOR = System.console() != null && System.getenv("TERM") != null && !System.getenv("TERM").equals("dumb");

  public static void main(String... args) throws ClassNotFoundException {
    String[] classAndMethod = args[0].split("#");
    String classFilepath = args[1];
    String quickfixFile = args[2];

    Color.BLUE_BRIGHT.print();
    System.out.println("> running " + args[0]);
    Color.RESET.print();

    List<DiscoverySelector> selectors = new ArrayList<>(1);
    if (classAndMethod.length > 1) {
      selectors.add(DiscoverySelectors.selectMethod(classAndMethod[0], classAndMethod[1]));
    } else {
      selectors.add(DiscoverySelectors.selectClass(classAndMethod[0]));
    }

    SummaryGeneratingListener listener = new SummaryGeneratingListener();

    LauncherDiscoveryRequest request = LauncherDiscoveryRequestBuilder.request().selectors(selectors).build();
    Launcher launcher = LauncherFactory.create();
    TestPlan testPlan = launcher.discover(request);
    launcher.registerTestExecutionListeners(listener);
    launcher.execute(request);

    TestExecutionSummary summary = listener.getSummary();
    PrintWriter out = new PrintWriter(System.out);
    summary.printFailuresTo(out);
    summary.printTo(out);

    // TODO: write failures to the quickfix file, see JUnit4TestRunner for an example
    for (TestExecutionSummary.Failure failure : summary.getFailures()) {
      failure.getTestIdentifier().getSource().ifPresent(source -> {
        // this always seems to be a MethodSource, which has no file location information apparently...
        if (source instanceof ClassSource) {
          ClassSource classSource = (ClassSource) source;
          System.out.println(classSource.getPosition());
        }
        // TODO: work for methods
      });
    }
  }

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
