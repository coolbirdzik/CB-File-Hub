# Picked up automatically by Flutter's Gradle plugin, which turns on R8 for
# release builds.

# slf4j-api arrives transitively and looks up its logging binder reflectively.
# No binding ships with the app and nothing here logs through slf4j, so R8 only
# needs to stop treating the absent class as an error. This is the rule AGP
# itself emits in build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn org.slf4j.impl.StaticLoggerBinder
