plugins {
    kotlin("jvm") version "2.3.21"
}

repositories {
    mavenCentral()
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

sourceSets {
    main {
        kotlin {
            srcDir("../app/src/main/kotlin")
            include("dev/termphin/ssh/RingBuffer.kt")
            include("dev/termphin/ssh/TerminalModeTracker.kt")
            include("dev/termphin/ssh/SnippetMarkerTracker.kt")
        }
    }
    test {
        kotlin {
            srcDir("../app/src/test/kotlin")
            include("dev/termphin/ssh/RingBufferTest.kt")
            include("dev/termphin/ssh/TerminalModeTrackerTest.kt")
            include("dev/termphin/ssh/SnippetMarkerTrackerTest.kt")
        }
    }
}

tasks.test {
    useJUnit()
}
