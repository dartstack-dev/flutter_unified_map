/// Stand-in for `flutter_web_plugins`' `Registrar` outside the web, where that library cannot be imported:
/// Windows and Linux call `registerWith()` without a registrar.
abstract class Registrar {}
