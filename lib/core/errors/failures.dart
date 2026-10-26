abstract class Failure {
  const Failure(this.message);

  final String message;
}
// added a comment
class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
