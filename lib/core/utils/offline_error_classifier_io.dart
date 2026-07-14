import 'dart:io';

bool isConnectionFailure(Object error) =>
    error is SocketException || error is HandshakeException;
