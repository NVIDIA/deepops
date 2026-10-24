"""Strict, deliberately bounded CLI grammar for the offline Run:ai tests."""
import sys


def fail(message):
    sys.stderr.write(message + '\n')
    raise SystemExit(1)


def parse(argv, valued, flags):
    """Keep positional order; reject unknown flags and missing option values."""
    positional, options = [], {}
    index = 0
    while index < len(argv):
        arg = argv[index]
        if not arg.startswith('-') or arg == '-':
            positional.append(arg)
        else:
            key, sep, value = arg.partition('=')
            if key in valued:
                if not sep:
                    index += 1
                    if index == len(argv) or (argv[index].startswith('--')):
                        fail('missing value for ' + key)
                    value = argv[index]
                options[key] = value
            elif key in flags and not sep:
                options[key] = True
            else:
                fail('unsupported option: ' + arg)
        index += 1
    return positional, options


def count(args, expected):
    if len(args) != expected:
        fail('expected %d positional arguments, got %r' % (expected, args))
