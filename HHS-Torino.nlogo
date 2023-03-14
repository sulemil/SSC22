extensions [ gis csv time ]

patches-own [ is-a-street color-p ]

breed [ patients patient ]
breed [ relatives relative ]
breed [ teams team ]
breed [ clouds cloud ]

globals[
  torino

  monitor-days monitor-hours monitor-minutes
  pat-add
  streets
  to-viab

  td              ;; the tick-datetime
  needs-names     ;; the complete list of procedures
  needs-times     ;; the list of times
  discharged      ;; to count discharged patients
  monitor-date    ;; to visualize the actual date

  closest-patches ;; total emissions
  tot-emissions-pat-hos
  tot-emissions-rel-hos
  tot-emissions-tea-hhs

  coords          ;; addresses of patients
  monit-patients

  hospital-queue  ;; variable used in the HOS scenario as a list of patients arrived in the H.
]


patients-own [
  need-list           ;; list of procedures/needs for each patient
  state               ;; "not-active", waiting or service
  restore-state       ;;
  first-time?         ;; to set the initial task ("TakeCharge")

  direction           ;; in hospital scenario
  speed               ;; idem
  emissions
  endTimeService
  theteam

  related
]

teams-own [
  daily-patients      ;; list of the patients for that day
  next-patient        ;; the next patient the team is reaching
  state               ;; the state of the team: not-working-time, waiting, moving, working, ...
  restore-state       ;;
  endTimeWork         ;; the time a turtle stop their work
  emissions           ;; Emissioni di CO2: gr/km 80
  destination
  speed         ;; the speed of the turtle
 ]

relatives-own [
  house               ;; their house (the patient's one)
  direction
  state
  speed
  startTimeAssistance
  endTimeAssistance
  emissions
]


;; ---------- SETUP HHS SCENARIO -------------

to setup
  ca

  setup-variables  ; create the environment
  setup-patients   ; create patients
  setup-teams      ; setup the teams (represented by vehicle)

  setup-initial-time
  reset-ticks
end


to setup-variables
  ; list of names of procedures and their corresponding time
  set needs-names ["TAKE-CHARGE" "PROCEDURE" "STRUCTURED-VISIT" "MEDICAL-VISIT" "NURSE-VISIT" "MIDLINE" "ECOGRAPHY" "ECG" "BLOOD-EXAM" "INFUSION" "MULTIPLE-INFUSION" "URGENCY" "TRASF-1" "TRASF-2" "TR-1" "MEDICATION-MIDLINE" "MEDICATION-DECUBITS" "ENEMA" "TRAININGCAREGIVER" "PSICH-SUPPORT" "DISMISSION"]
  set needs-times [90 10 30 20 10 40 20 15 5 5 5 15 20 45 10 30 10 15 20 20 25]

  ask patches [ set pcolor 49.5  set is-a-street false ]

  set discharged 0              ; monitors initially set to 0
  set tot-emissions-pat-hos 0   ;
  set tot-emissions-rel-hos 0   ;
  set tot-emissions-tea-hhs 0   ;

  setup-gis
end

to setup-gis
  gis:load-coordinate-system "gz_str_2022.prj"   ; GIS setup

  set torino gis:load-dataset "gz_str_2022.shp"  ; shapefile
  ;gis:apply-coverage torino "TIPO_AREA" l
  ;gis:set-drawing-color orange
  ;gis:draw torino 0.3

  set to-viab gis:load-dataset "ac_vei_2022.shp"  ; shapefile

  gis:set-drawing-color 2
  gis:draw to-viab 0.7

  gis:set-world-envelope gis:envelope-of to-viab

  ask patches gis:intersecting to-viab
   [ set is-a-street true ]

  set streets patches with [is-a-street = true]   ;;; print count streets
end

to setup-patients
  setup-coords

  repeat 25 [
    create-patients 1 [ ; initially create 30 patients
      set monit-patients monit-patients + 1
      let punto one-of coords
      setxy item 0 punto item 1 punto

      features-of-patient
    ]
  ]
end

to setup-coords
  set coords []

  let file "addr.csv"
  file-open file

  while [ not file-at-end? ] [
    let row csv:from-row file-read-line

    let lat item 6 row
    let lon item 7 row

    let gis-lat-lon gis:project-lat-lon lon lat

    set coords lput (list item 0 gis-lat-lon item 1 gis-lat-lon) coords
  ]

  file-close
end

to features-of-patient
  let punto one-of coords

  setxy item 0 punto item 1 punto

  set shape "person" set color sky

  set state "not-active"

  ;attribute needs
  set need-list ["TAKE-CHARGE"]

  let needs-names-pat remove "TAKE-CHARGE" needs-names
  set needs-names-pat remove "DISMISSION" needs-names-pat
  set needs-names-pat remove "TRASF-2" needs-names-pat
  set needs-names-pat remove "URGENCY" needs-names-pat

    ; un caso su 3 no midline
    let n ""
    if random 3 = 0 [
      set needs-names-pat remove "MIDLINE" needs-names-pat
    ]

  ;; create a set of procedures
  repeat 3 + random 20 [

    set n one-of needs-names-pat

    set need-list lput n need-list

    ;se trasf-1 >> allora trasf-2 in seguito
    if n = "TRASF-1" [
      set need-list lput "TRASF-2" need-list
    ]
  ]
    other-check

    set speed 2

  set need-list lput "DISMISSION" need-list
end

to other-check
  if member? "STRUCTURED-VISIT" need-list and member? "MEDICAL-VISIT" need-list and member? "NURSE-VISIT" need-list
    [
      check-and-change
      check-and-change
    ]

    if member? "MIDLINE" need-list
    [
      if length  filter [ s -> s = "MIDLINE" ] need-list < 2 [
      let pos position "MIDLINE" need-list
      let l (length need-list - pos)
      let fr int (l / 5) - 1
      if fr > 0 [
          repeat fr [
            let p pos + fr + random 2
            if p < length (need-list) [
              set need-list insert-item p need-list "MIDLINE"
              set p p + fr
            ]
          ]
        ]
      ]
    ]
end


to check-and-change
      let posS position "STRUCTURED-VISIT" need-list
      let posM position "MEDICAL-VISIT" need-list
      let posN position "NURSE-VISIT" need-list

      if (posS > posM) [
       ifelse (posM > posN) [ ;this is the situation where posN - posM - posS  ==>  the solution is inverting posN and posS
          set need-list replace-item posN need-list "STRUCTURED-VISIT"
          set need-list replace-item posS need-list "NURSE-VISIT"
        ]
        [ ifelse posN > posS [ ;this is the situation where posM - posS - posN  ==>
            set need-list replace-item posM need-list "STRUCTURED-VISIT"
            set need-list replace-item posS need-list "MEDICAL-VISIT"
          ][ ;this is the situation where posM - posN - posS  ==>
            set need-list replace-item posM need-list "STRUCTURED-VISIT"
            set need-list replace-item posN need-list "MEDICAL-VISIT"
            set need-list replace-item posS need-list "NURSE-VISIT"
          ]
         ]
      ]
  if (posS > posN) [
    if (posM > posS) [  ;  N-S-M
          set need-list replace-item posN need-list "STRUCTURED-VISIT"
          set need-list replace-item posS need-list "MEDICAL-VISIT"
          set need-list replace-item posM need-list "NURSE-VISIT"
    ]
  ]
end

to setup-teams
  create-teams 5 [
    set color white
    set shape "amb"
    set size 8
    set state "not-working-time"
    set daily-patients []
    set destination 0
    setxy 12 -34
    set emissions 0
  ]
  ask teams [set speed 2 ]
end

to setup-initial-time
  set td time:anchor-to-ticks "2022-01-02 00:00:00.000" 1 "minute"
  set monitor-date (word time:get "day" td "/" time:get "month" td  "/" time:get "year" td " - " time:get "hour" td  ":"  time:get "minutes" td  " " ); time:get "second" td ) ; ":" time:get "milli" td )
end
;;; --x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x
;;; --x--x--x--x--x--x--x--x--x-|    GO HHS   |-x--x--x--x--x--x--x--x--x--x
;;; --x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x--x

to go
  tick
  update-time   ;; monitor
  if monit-patients = 700 or monitor-date = "31/3/2023 - 23:59 "  [stop]  ;; stop condition
  arrival-of-a-new-patient
  planning-at-9
  teams-start-at-10
  check-for-another-patient
  moving-to-next-patient
  check-working-time
  stop-work-at-18
end

to arrival-of-a-new-patient
  if time:get "hour" td = 8 and time:get "minute" td = 0 and monit-patients < 700
    [
      if by-night? [ ask patches [ set pcolor 49.5 ] ]

      create-patients 1 [
      set monit-patients monit-patients + 1
        features-of-patient ]
    ]
end

to update-time
  set monitor-date (word time:get "day" td "/" time:get "month" td  "/" time:get "year" td " - " time:get "hour" td  ":"  time:get "minutes" td  " " ); time:get "second" td ) ; ":" time:get "milli" td )
end

to planning-at-9
  if time:get "hour" td = 9 and time:get "minute" td = 0
    [ ask teams
      [ if any? patients with [ state = "not-active" ]
        [ let a-patient-not-active one-of patients with [ state = "not-active" ]
          set daily-patients lput a-patient-not-active daily-patients
          ask a-patient-not-active [ set state "waiting" ]

          repeat (2 + random 2) [
            if any? patients with [ state = "not-active" ]
            [
              set a-patient-not-active one-of patients with [ state = "not-active" ]
              set daily-patients lput a-patient-not-active daily-patients
              ask a-patient-not-active [ set state "waiting" ]
            ]
          ]
        ]
        ;print (word "...all'inizio i pazienti sono: " daily-patients)
        ;print length daily-patients
      ]
    ]
end

to teams-start-at-10
  if (time:get "hour" td = 10 and time:get "minute" td = 0)
    [
    if any? teams with [ state = "not-working-time" ]
      [
        ask teams with [ state = "not-working-time" ][
          set state "looking-for-next-patient"
        ]
      ]
    ]
end

to check-for-another-patient
  if any? teams with [ state = "looking-for-next-patient" and not empty? daily-patients ]
    [
      ask teams with [ state = "looking-for-next-patient" and not empty? daily-patients ] [

        set next-patient first daily-patients
        set daily-patients remove first daily-patients daily-patients


        ;set heading towards next-patient
        set state "moving"
        ask next-patient [ set size 7 set color 11 + random 6 ]
        ;print (word " inizia a muoversi alle " td " verso prox paz: " [who] of next-patient)
      ]
    ]
end

to moving-to-next-patient
  ask teams
    [
      if state = "moving"
      [
        ifelse member?  next-patient turtles-on patches in-cone 4 60
        [
          set state "working"

          let pos position first [need-list] of next-patient needs-names

          let nt item pos needs-times
          set endTimeWork time:plus td nt "minutes"

          if event-log?
          [ output-print  (word [who] of next-patient  "," first [need-list] of next-patient "," time:show td "yyyy-MM-dd HH:mm" "," (word "Team" who) )
          ]


          ;print(word "inizia a lavorare alle " td " con " [who] of next-patient " fino alle " endTimeWork)
          ask next-patient [ set state "service" set size 7 set color green]
        ]
        [ ifelse [is-a-street] of patch-ahead speed = true
          [ fd speed
            set emissions emissions + 30
            set tot-emissions-tea-hhs tot-emissions-tea-hhs + 30
          ]
          [
           turn-until-a-road
          ]
        ]
      ]
    ]
end


to check-working-time
  ask teams
    [
      if state = "working"
      [
        if time:is-after? td [ endTimeWork ] of self [
          ifelse time:get "hour" td < 19 [
            set state "looking-for-next-patient"
            ;print(word "smette di lavorare con "  [who] of next-patient " e alle " td " torna a cercare tra -> "  daily-patients )
          ]
          [
            set state "not-working-time"
          ]

          ask next-patient [

            set need-list remove first need-list need-list

            if empty? need-list [  set discharged discharged + 1 die ]
            set size 0
            set state "not-active"
          ]
        ]
      ]
  ]
end

to stop-work-at-18
  if time:get "hour" td = 18  and time:get "minute" td = 0
  [

    if by-night? [ ask patches [ set pcolor 91.5 ] ]

    ask teams
    [ ;print state
      ifelse state != "working"
      [
        set state "not-working-time"
      ][
        ;print next-patient
        ;print (word "alle 18 ha ancora questi da lavorare : " daily-patients )
      ]
    ]
  ]
end

to turn-until-a-road
  face next-patient
  ifelse [is-a-street] of patch-ahead speed [ fd speed ]
    [
    let angle 90
    set closest-patches patches in-cone 5 angle

    let nearest-street find-a-patch-here closest-patches angle

    ;print [pxcor] of close-turtles with [is-a-street = true] ;[distance myself]
    ;print patch-here
    ;print nearest-street
    ;ifelse nearest-street != nobody [

    ifelse  nearest-street  != nobody [
        ;print distance nearest-street
        face nearest-street
        fd distance nearest-street

        ]
      [ let ns one-of patches with [is-a-street = true] in-radius 2
        face ns
        fd distance ns  ]
    ]
end



to-report find-a-patch-here [closestp a]
    let clop 0

    let nearest-street one-of closestp with [is-a-street = true] ;[distance myself]

    ifelse nearest-street != patch-here [
      set clop nearest-street
    ]
    [
      set clop find-a-patch-here (patches in-cone 10 (a + 10)) (a + 10)
    ]
  report clop
end




; -X-X-X-X-X-X-X-X-X-X-X-X-X-X-X-

























to setup-hospital

  ca

  setup-variables-h  ;create-environment

  setup-patients-h  ;create-pat

  setup-teams-h  ;setup-cars

  setup-initial-time-h

  reset-ticks

end



to setup-variables-h  ;create-environment
  set needs-names ["TAKE-CHARGE" "PROCEDURE" "STRUCTURED-VISIT" "MEDICAL-VISIT" "NURSE-VISIT" "MIDLINE" "ECOGRAPHY" "ECG" "BLOOD-EXAM" "INFUSION" "MULTIPLE-INFUSION" "URGENCY" "TRASF-1" "TRASF-2" "TR-1" "MEDICATION-MIDLINE" "MEDICATION-DECUBITS" "ENEMA" "TRAININGCAREGIVER" "PSICH-SUPPORT" "DISMISSION"]
  set needs-times [90 10 30 20 10 40 20 15 5 5 5 15 20 45 10 30 10 15 20 20 25]

  set discharged 0

  ask patches [ set pcolor 49.5  set is-a-street false ]
  set hospital-queue []
  setup-gis
end

to setup-patients-h  ; create 700 patients on a GIS map

  setup-coords
  repeat 25 [
  create-patients 1 [ ;700
     set monit-patients monit-patients + 1
     let punto one-of coords
     setxy item 0 punto item 1 punto

     features-of-patient
     set state "moving"
     set direction patch 9 -33
     setup-relatives-h
     set size 7
  ]
  ]
end

to setup-teams-h  ;setup-cars
   create-teams 1 [
    set color white
    set shape "person doctor"
    set size 8
    set state "not-working-time"
    ;set daily-patients []
    set destination 0
    setxy 12 -34
    set emissions 0
  ]
end

to setup-relatives-h   ; create realtives and set variable related
  ifelse random 10 < 9  ;; 90% has at least one relative
    [  hatch-relatives 1 [ set size 7 set shape "person" set house patch-here set color orange set state "house" let aa self ask myself [set related aa] ]
    ][ set related nobody   ; initialize empty the relatives/caregivers/partner/parents
    ]
end

to setup-initial-time-h
 set td time:anchor-to-ticks "2022-01-02 00:00:00.000" 1 "minute"
  set monitor-date (word time:get "day" td "/" time:get "month" td  "/" time:get "year" td " - " time:get "hour" td  ":"  time:get "minutes" td  " " ); time:get "second" td ) ; ":" time:get "milli" td )
end

to slow
  if (speed > 0)
  [set speed speed - 1]
end

to speed-up
  if ([pcolor] of patch-ahead 2 != white) and (not any? turtles-at 0 1)
   [ set speed speed + 1]
end

to open-file-patients-address
  set pat-add csv:from-file "CSV-civici/sample.csv"
end

to setup-monitors
  set monitor-hours 0
  set monitor-minutes 0
  set monitor-days 0
end

;;; CREARE I TEAMS CON LE CARATTERISTICHE DAL FiLE GOING
;  units operating on the territory (UOT):
; group consisting of 1 doctor and 1 nurse
; group consisting of 1 nurse only
; group consisting of 2 nurses for performing complex procedures.






;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;-------------------;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;|        GO         |;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;-------------------;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go-hospital
  tick
  update-time-h   ;; monitor

  if monit-patients = 700 or monitor-date = "31/3/2023 - 23:59 "  [stop]  ;; stop condition

  arrival-of-a-new-patient-h   ;; at 8h wvery moring new arrival of 3-7 patients

  teams-start-at-9-h        ;; at 10 start work
  teams-looking

  moving-to-hospital
  moving-to-hospital-relatives

  check-assistance-time-r

  check-working-time-h

  stop-work-at-18-h
end

to update-time-h
  set monitor-date (word time:get "day" td "/" time:get "month" td  "/" time:get "year" td " - " time:get "hour" td  ":"  time:get "minutes" td  " " )
end

to arrival-of-a-new-patient-h
    if time:get "hour" td = 8 and time:get "minute" td = 0
    [

      if by-night? [ ask patches [ set pcolor 49.5 ] ]

      if random 5 = 1 [
      let npat 1 ;(1 + random 5)
      set monit-patients monit-patients + npat
      repeat npat [
        create-patients 1 [
          features-of-patient
          setup-relatives-h

          set direction patch 9 -33
          set state "moving"

          if related != nobody [
            ask related [
              set house patch-here
              set startTimeAssistance time:plus td (20 + random 100) "minutes"  ; set when the relative starts to go for assistance at the H
              set state "waiting-to-go-for-assistance"
              set size 7
              set direction patch 9 -33
            ]
          ]
        ]
      ]
    ]
    ]
end

to teams-start-at-9-h
  if (time:get "hour" td = 9 and time:get "minute" td = 0)
    [ if any? teams with [ state = "not-working-time" ]
      [ ask teams with [ state = "not-working-time" ][
          set state "looking-for-next-patient"
        ]
      ]
  ]
end

to teams-looking
     if any? teams with [ state = "looking-for-next-patient"] and not empty? hospital-queue      ; and not empty? daily-patients ]
      [ ask teams with [ state = "looking-for-next-patient" ]                                    ; and not empty? daily-patients ]
       [
          set next-patient first hospital-queue; daily-patients  ;; set the first patient in the list as "next-patient"
          set hospital-queue remove next-patient hospital-queue  ;; remove the first patient from the list

          ;print (word "lo state del worker sarebbe: " state)
          set state "working"

          ;; compute the duration of the working time
          let pos position first [need-list] of next-patient needs-names
          let nt item pos needs-times  + 30 + random (150)
          set endTimeWork time:plus td nt "minutes"

          if event-log?
           [
           output-print (word [who] of next-patient  "," first [need-list] of next-patient "," time:show td "yyyy-MM-dd HH:mm" )
           ]
        ]
      ]
end

to moving-to-hospital
  ask patients
    [ if state = "moving"
      [
        ifelse member? direction patches in-cone 4 60
        [ ; the patient starts the service (team is "working")

          set state "waiting-for-starting-the-service"
          ;print(self)
          set hospital-queue lput self hospital-queue
        ]
        [
          ; move !!
          ifelse [is-a-street] of patch-ahead speed = true
          [
            fd speed
            set emissions emissions + 30
            if smog? [if random 10 = 1 [hatch-clouds 1 [set color 5 + random 4 set shape "cloud" set size 7 + random 12]]]
            set tot-emissions-pat-hos tot-emissions-pat-hos + 30
          ]
          [
            turn-until-a-road-h
          ]
        ]
      ]
    ]
end

to moving-to-hospital-relatives
  ask relatives
    [ if state = "waiting-to-go-for-assistance" [
        if time:is-after? td startTimeAssistance
        [ set state "moving"  ]
      ]

      if state = "moving"
      [ ifelse member? direction patches in-cone 4 60   ; if they are arrived...
        [ ;
          ifelse member? house patches in-cone 4 60    ;
          [ ; if they are arrived at home
            set state "waiting-to-go-for-assistance" ; set direction patch 9 -33
            set startTimeAssistance time:plus td (240 + random 1440) "minutes"
              set direction patch 9 -33
          ]
          [ ; if the relative/caregiver arrived at the hospital
            set endTimeAssistance time:plus td (30 + random 60) "minutes"
            set state "assistance"
          ]
        ]
        [ ; if they are not arrived in ther "direction", then move...
          ifelse [is-a-street] of patch-ahead speed = true
          [
            fd speed
            set emissions emissions + 30
            set tot-emissions-rel-hos tot-emissions-rel-hos + 30
          ]
          [
           turn-until-a-road-h
          ]
        ]
      ]
    ]
end

to check-assistance-time-r
  ask relatives
    [
      if state = "assistance"
      [ if time:is-after? td endTimeAssistance  [
          set direction house
          set state "moving"
        ]
      ]
  ]
end

to check-working-time-h
  ask teams
    [
      if state = "working"
      [
        if time:is-after? td endTimeWork [

          set state "looking-for-next-patient"

          ask next-patient [
             set need-list remove first need-list need-list

             ifelse not empty? need-list [  ; the patient wait for another procedure/team
                set hospital-queue lput self hospital-queue
            ][
             set discharged discharged + 1
              if related != nobody [ ask related [ die ] ]
              die
            ]
          ]
        ]
      ]
  ]
end


to stop-work-at-18-h
  if time:get "hour" td = 18  and time:get "minute" td = 0
  [
    if by-night? [ ask patches [ set pcolor 91.5 ] ]

    ask teams
    [ set state "not-working-time"   ;"not-working-now"
      set restore-state state

      if next-patient != [] and next-patient != nobody [
        ask next-patient [ set restore-state state set state "pause" ]
      ]
    ]
  ]
end

to turn-until-a-road-h
  face direction
  ifelse [is-a-street] of patch-ahead speed [ fd speed ]
    [
      let angle 90
   set closest-patches patches in-cone 5 angle

   let nearest-street find-a-patch-here closest-patches angle

    ifelse  nearest-street  != nobody [
        face nearest-street
        fd distance nearest-street

        ]
      [ let ns one-of patches with [is-a-street = true] in-radius 2
        face ns
        fd distance ns  ]
    ]
end


to-report find-a-patch-here-h [closestp a]
    let clop 0

    let nearest-street one-of closestp with [is-a-street = true] ;[distance myself]

    ifelse nearest-street != patch-here [
      set clop nearest-street
    ]
    [
      set clop find-a-patch-here (patches in-cone 20 (a + 20)) (a + 20)
    ]
  report clop
end
@#$#@#$#@
GRAPHICS-WINDOW
251
10
861
621
-1
-1
2.0
1
12
1
1
1
0
0
0
1
-150
150
-150
150
0
0
1
ticks
30.0

BUTTON
6
39
99
85
SETUP
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
100
39
193
85
GO
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

BUTTON
194
52
249
85
go-once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
864
382
1044
427
#Patients having a service
count patients with [ state = \"service\" ]
17
1
11

SLIDER
874
663
1053
696
n-doctors-struct
n-doctors-struct
0
6
0.0
1
1
NIL
HORIZONTAL

SLIDER
874
729
1053
762
n-nurses
n-nurses
0
5
5.0
1
1
NIL
HORIZONTAL

SLIDER
874
696
1053
729
n-doctors-juinior
n-doctors-juinior
0
5
3.0
1
1
NIL
HORIZONTAL

MONITOR
257
16
405
61
Date of the simulation
monitor-date
17
1
11

MONITOR
735
571
856
616
Patients discharged
discharged
17
1
11

OUTPUT
6
86
249
574
11

MONITOR
6
576
249
621
TOT-emissions-(CO2)-HHS
tot-emissions-tea-hhs
17
1
11

BUTTON
863
41
953
87
SETUP HOS
setup-hospital
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
874
630
938
663
reset-file
 let file \"CSV-civici/addr.csv\"\n\n  file-open file\nfile-close
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
865
336
1044
381
#Patients
count patients
17
1
11

BUTTON
954
41
1043
87
GO HOS
go-hospital
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
988
88
1043
121
go-hos1
go-hospital
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
863
173
1043
218
TOT-emissions-CO2-HOS-PAT
tot-emissions-pat-hos
17
1
11

MONITOR
863
219
1043
264
TOT-emissions-CO2-HOS-REL
tot-emissions-rel-hos
17
1
11

MONITOR
865
474
1044
519
#Relatives involved
count relatives
17
1
11

MONITOR
865
428
1044
473
QUEUE-Hospital
length hospital-queue
17
1
11

TEXTBOX
866
319
1016
337
HOS Scenario - Indicators
12
0.0
1

SWITCH
863
88
953
121
smog?
smog?
0
1
-1000

SWITCH
864
588
967
621
by-night?
by-night?
1
1
-1000

SWITCH
121
533
226
566
event-log?
event-log?
0
1
-1000

TEXTBOX
5
11
276
53
Hospital-at-Home Service (HHS) 
15
102.0
1

TEXTBOX
869
16
1057
34
Hospital scenario (HOS)
15
0.0
1

@#$#@#$#@
## WHAT IS IT?

A demo model (GIS-based) for understanding reinforcement learning, with a car agent that have to learn a path to reach up to 5 stops.

## HOW TO USE IT

Select the number of stops, then Setup the model.

Press GO to observe the learning process, as well as the best route learned by the car agent.

## THINGS TO NOTICE

Deselect the "View updates" button to increase the speedy.

The car agent do not interach with GIS variables during their movements.

## RELATED MODELS

This model extends with movements in 8 directions and GIS the RL Maze model:
http://ccl.northwestern.edu/netlogo/models/community/Reinforcement%20Learning%20Maze

## CREDITS AND REFERENCES

ABBPS
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

amb
false
0
Rectangle -7500403 true true 30 90 210 195
Polygon -7500403 true true 296 190 296 150 259 134 244 104 210 105 210 190
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Circle -16777216 true false 69 174 42
Rectangle -1 true false 288 158 297 173
Rectangle -1184463 true false 289 180 298 172
Rectangle -2674135 true false 29 151 298 158
Line -16777216 false 210 90 210 195
Rectangle -16777216 true false 83 116 128 133
Rectangle -16777216 true false 153 111 176 134
Line -7500403 true 165 105 165 135
Rectangle -7500403 true true 14 186 33 195
Line -13345367 false 45 135 75 120
Line -13345367 false 75 135 45 120
Line -13345367 false 60 112 60 142
Rectangle -16777216 true false 30 90 30 90
Rectangle -16777216 true false 15 75 30 180
Rectangle -16777216 true false 30 75 210 90
Rectangle -16777216 true false 135 75 165 90

ambulance
false
0
Rectangle -7500403 true true 30 90 210 195
Polygon -7500403 true true 296 190 296 150 259 134 244 104 210 105 210 190
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Circle -16777216 true false 69 174 42
Rectangle -1 true false 288 158 297 173
Rectangle -1184463 true false 289 180 298 172
Rectangle -2674135 true false 29 151 298 158
Line -16777216 false 210 90 210 195
Rectangle -16777216 true false 83 116 128 133
Rectangle -16777216 true false 153 111 176 134
Line -7500403 true 165 105 165 135
Rectangle -7500403 true true 14 186 33 195
Line -13345367 false 45 135 75 120
Line -13345367 false 75 135 45 120
Line -13345367 false 60 112 60 142

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cloud
false
0
Circle -7500403 true true 13 118 94
Circle -7500403 true true 86 101 127
Circle -7500403 true true 51 51 108
Circle -7500403 true true 118 43 95
Circle -7500403 true true 158 68 134

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person doctor
false
0
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Polygon -13345367 true false 135 90 150 105 135 135 150 150 165 135 150 105 165 90
Polygon -7500403 true true 105 90 60 195 90 210 135 105
Polygon -7500403 true true 195 90 240 195 210 210 165 105
Circle -7500403 true true 110 5 80
Rectangle -7500403 true true 127 79 172 94
Polygon -1 true false 105 90 60 195 90 210 114 156 120 195 90 270 210 270 180 195 186 155 210 210 240 195 195 90 165 90 150 150 135 90
Line -16777216 false 150 148 150 270
Line -16777216 false 196 90 151 149
Line -16777216 false 104 90 149 149
Circle -1 true false 180 0 30
Line -16777216 false 180 15 120 15
Line -16777216 false 150 195 165 195
Line -16777216 false 150 240 165 240
Line -16777216 false 150 150 165 150

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.3.0-beta1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment1" repetitions="100" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>tot-emissions-tea-hhs</metric>
    <enumeratedValueSet variable="n-doctors-struct">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-doctors-juinior">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="smog?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="by-night?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nurses">
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment2" repetitions="10" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>tot-emissions-tea-hhs</metric>
    <enumeratedValueSet variable="n-doctors-struct">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-doctors-juinior">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="smog?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="by-night?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nurses">
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment3" repetitions="100" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup-hospital</setup>
    <go>go-hospital</go>
    <metric>tot-emissions-pat-hos</metric>
    <metric>tot-emissions-rel-hos</metric>
    <enumeratedValueSet variable="n-doctors-struct">
      <value value="6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-doctors-juinior">
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="smog?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="by-night?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nurses">
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
