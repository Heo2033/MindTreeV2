import { ALPHABET_RULE, NO_META_RULE } from "./rules.js";
import { resolveCorrectAnswerIndex } from "../lib/optionMatching.js";
import { shortIdWith } from "../domain/shortIds.js";

export interface AssessmentPromptContext {
  topic: string;
  goal: string;
  sessionItems: Array<{ nodeId: string; label: string; oneLiner: string; details: string }>;
  includeApplication: boolean;
}

export const PROMPT_ASSESSMENT = `#            »    
                             ·   °       µ       °             .                    µ        ,        µ                              µ   »                »                »       ·           °        µ   »                                  ·   °           »   µ                                                                     °                     µ         .

#                     µ             
       µ       °: "{{topic}}"
   ¦   µ   »                »       ·           °        µ   »    : {{goal}}
       ·            µ                µ                               (            °           °    ¦        µ                ):
{{session_items}}

#                                                    (           µ                 ¦ 6)
           µ       µ                                      °   »                                    µ            ,                    »       ·                »   µ                °       µ                   :
- **recognition**                ·       °       °           µ:             ±   µ                            µ                               °           °                 ·         µ                       ¦ (                        »                       °,    °        µ    ·   °                    °           µ)
- **recall**                                            °           µ:                                ·       µ                        µ       µ   »   µ           µ        »            »            µ                      °          (multiple choice)
- **explanation**                ±                            µ    ¦   °           ·                                     »           °         (structure matters; rubric        ±       ·   °        µ   »   µ    )
- **diagnosis**                °                          ±                             ¬       ±        /       µ                        µ                         µ                         µ                                          µ       ¶       µ             (rubric        ±       ·   °        µ   »   µ    )
- **application**                            µ            ·       °           µ                                                   µ                                       °              (rubric        ±       ·   °        µ   »   µ    )
- **transfer**                µ       µ       µ            ·       °           µ        °            µ   ¶            /       µ            °           °                                          °              (rubric        ±       ·   °        µ   »   µ    )

            µ         {{question_count}}                                 .        ±   µ           µ                 °   ·               ±       °   ·       µ                      :                          »   ¶   µ        ±                       µ                           ·   °       µ    ,    °        µ             »                     °                »                .
        »     recognition/recall            °   ¶     options      correctAnswer (               µ                            µ                                 °           °            °,        °                °          0).
        »     explanation/diagnosis/application/transfer         options=[]      correctAnswer=""; explanation (           ±               °)                µ       ¶                                 µ                 µ                     µ                         µ               °            :        °           µ        »   µ       µ                          »   ¶                                                           °                              ±                                     µ        µ.

#    ¤               °                      µ        °
                               JSON-       ±       µ         :
{"questions":[{"id":"a1","type":"recall","nodeId":"n2_a","question":"...","options":["A","B","C","D"],"correctAnswer":"0","explanation":"..."},{"id":"a2","type":"explanation","nodeId":"n2_b","question":"       ±                            µ                                 »           °        ,        °            °   ±            °   µ      X (                                 ¬   °            ,                                  -       »   µ                    µ                µ                ·    ).","options":[],"correctAnswer":"","explanation":"       »            µ            µ        »   µ       µ                               µ        °: 1) ..., 2) ..."}]}

#                    µ        °            
- correctAnswer        »     recognition/recall                                               °           »                            °           °            ° (                        ° "0","1","2","3").
-                                                   µ                         »       ±               µ                        °           µ,        µ                µ        ¦                                      °                »                .

${NO_META_RULE}
${ALPHABET_RULE}

#        ·         
                µ        °                                       °                                     ·            µ.                               ,        °           °              ,            ±                                °                             .

               °                         µ                °            µ JSON.         µ   · \`\`\`json         ±   µ   ·                        µ             .

#                    µ                µ       µ                     µ             
- [ ]                      {{question_count}}                                 
- [ ]                                                       options (recognition/recall)                                         µ                               (explanation/diagnosis/application/transfer)
- [ ]                 µ    ¦                                     ¦                                  rubric (explanation)                µ       ¶                                 µ                 µ                     µ            
- [ ]                                                   µ                         »       ±               µ                        °           µ,        µ                µ        ¦                                      °                »                
- [ ]    ¤               °                                        JSON             »                  "questions"`;
