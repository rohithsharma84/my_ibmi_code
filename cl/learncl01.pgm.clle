/* Program    : LEARNCL01                                                    */
/* Author     : Rohit Sharma                                                 */
/* Created on : 2025-05-14                                                   */
/* %TEXT: Accept 1 input parm and send a message                             */
/* Usage      : CALL LEARNCL01 PARM(NAME)                                    */

START:      PGM PARM(&NAME)

            DCL &NAME *CHAR LEN(10)
            DCL &MSG *CHAR LEN(80)

        /* Check parameter count before touching parm storage */
            IF COND(%PARMS *LT 1) THEN(DO)
                CHGVAR &MSG VALUE('Parameter NAME is required.')
                SNDPGMMSG MSGDTA(&MSG) MSGID(CPF9898) MSGF(QCPFMSG) MSGTYPE(*ESCAPE)
            ENDDO

        /* Validate required input parm */
            IF COND(&NAME *EQ '          ') THEN(DO)
                CHGVAR &MSG VALUE('Parameter NAME is required.')
                SNDPGMMSG MSGDTA(&MSG) MSGID(CPF9898) MSGF(QCPFMSG) MSGTYPE(*ESCAPE)
            ENDDO

        /* Send a message to the pgm msg queue */
            CHGVAR &MSG VALUE('Hi' |> &NAME |< '! Welcome to Learning CL!')
            SNDPGMMSG MSGDTA(&MSG) MSGID(CPF9898) MSGF(QCPFMSG) MSGTYPE(*INFO)

EOP:        ENDPGM