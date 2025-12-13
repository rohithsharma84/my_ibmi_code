/* Program    : LEARNCL01                                                    */
/* Author     : Rohit Sharma                                                 */
/* Created on : 2025-05-14                                                   */
/* Description: Accept 1 input parameter and displays a message              */
/* Usage      : CALL LEARNCL01 PARM(NAME)                                    */
START:      PGM PARM(&NAME)

            DCL &NAME *CHAR LEN(20)
            DCL &MSG *CHAR LEN(80)

            CHGVAR &MSG VALUE('Hi' |> &NAME |< '! Welcome to Learning CL!')
            SNDPGMMSG MSGDTA(&MSG) MSGID(CPF9898) MSGF(QCPFMSG) MSGTYPE(*INFO)

EOP:        ENDPGM