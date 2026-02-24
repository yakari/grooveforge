Shell (command line) settings

shell.prompt
Type
String (str)
Default
(empty string)
In dump mode we set the prompt to "" (empty string). The ui cannot easily handle lines, which don't end with cr. Changing the prompt cannot be done through a command, because the current shell does not handle empty arguments.

shell.port
Type
Integer (int)
Min - Max
1 - 65535
Default
9800
The shell can be used in a client/server mode. This setting controls what TCP/IP port the server uses.
