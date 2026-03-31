/* Program    : LEARNCL02                                                    */
/* Author     : Rohit Sharma                                                 */
/* Created on : 2026-03-19                                                   */
/* %TEXT: Pass a parm to LEARNCL01                                           */
/* Usage      : CALL LEARNCL02 PARM(NAME)                                    */

START:      PGM PARM(&NAME)

            DCL VAR(&NAME) TYPE(*CHAR) LEN(10)

        /* Call LEARNCL01 with the parm */
            CALL PGM(LEARNCL01) PARM(&NAME)
            
EOP:        ENDPGM

