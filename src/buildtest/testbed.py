"""
A contrived CLI wrapper for whoami
"""

import logging

from whoami.whoami import whoami


def main() -> None:
    """
    Main entrypoint
    """

    logging.basicConfig(level=logging.INFO)
    me = whoami()
    logging.info('UID: %s', me.uid)
    logging.info('GID: %s', me.gid)
    logging.info('Username: %s', me.username)
    logging.info('Home: %s', me.homedir)
    logging.info('Shell: %s', me.shell)


if __name__ == '__main__':
    main()
