/// The one message shown for every backend or internal failure.
const internalErrorMessage = 'Internal Error, Try again later';

/// Statuses that mean the user's own input was rejected, so the form's
/// validation message applies instead of the internal error.
bool isInputRejectionStatus(int statusCode) =>
    statusCode == 400 || statusCode == 409 || statusCode == 422;

/// Statuses that mean the session or home is not verifiable.
bool isSessionRejectionStatus(int statusCode) =>
    statusCode == 401 || statusCode == 403;
