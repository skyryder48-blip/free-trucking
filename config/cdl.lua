--[[
    config/cdl.lua — CDL Test Question Pools

    Three pools: class_b (40), class_a (40), tanker (15).
    Server selects random subsets per test attempt.
    Questions use comedy-adjacent tone with accurate content.
]]

CDLQuestionPools = {}

-- =============================================================================
-- CLASS B — 40 Questions
-- General trucking knowledge, safety basics, vehicle inspection, road rules,
-- basic maneuvering. For the basic CDL (box trucks like the Benson).
-- =============================================================================
CDLQuestionPools.class_b = {
    -- 1
    {
        question = "Before you start your trip in a Benson, you should perform a pre-trip inspection. Which of the following is NOT part of a standard pre-trip?",
        options = {
            a = "Checking tire pressure and tread depth",
            b = "Testing all lights and reflectors",
            c = "Updating your social media status to 'on the road'",
            d = "Inspecting the braking system"
        },
        correct = 'c'
    },
    -- 2
    {
        question = "You're driving a box truck down Route 68 and your brakes start to fade on a long downhill. What is the most likely cause?",
        options = {
            a = "Overuse of brakes causing them to overheat",
            b = "The truck is haunted",
            c = "You forgot to release the parking brake this morning",
            d = "The road surface is too smooth"
        },
        correct = 'a'
    },
    -- 3
    {
        question = "What is the proper technique for navigating a long downgrade in a heavy vehicle?",
        options = {
            a = "Ride the brakes the entire way down to maintain control",
            b = "Put the transmission in neutral and coast to save fuel",
            c = "Use a lower gear and apply brakes intermittently with steady pressure",
            d = "Close your eyes and pray to the trucking gods"
        },
        correct = 'c'
    },
    -- 4
    {
        question = "The total stopping distance of a commercial vehicle is made up of which three components?",
        options = {
            a = "Perception distance, reaction distance, braking distance",
            b = "Following distance, turning distance, parking distance",
            c = "Engine distance, tire distance, road distance",
            d = "Speed distance, weight distance, weather distance"
        },
        correct = 'a'
    },
    -- 5
    {
        question = "How far ahead should a commercial vehicle driver scan the road in an urban environment?",
        options = {
            a = "One car length for every 10 mph",
            b = "At least one to two blocks or 12-15 seconds ahead",
            c = "As far as the hood ornament",
            d = "Only to the vehicle directly in front of you"
        },
        correct = 'b'
    },
    -- 6
    {
        question = "Your Benson's cargo doors keep flying open mid-route through Vinewood. What should you have done before departing?",
        options = {
            a = "Driven faster so the wind holds them shut",
            b = "Secured all cargo doors and checked latches during pre-trip inspection",
            c = "Tied them closed with your shoelaces",
            d = "Asked a pedestrian to hold them shut"
        },
        correct = 'b'
    },
    -- 7
    {
        question = "When driving a commercial vehicle, the 'four-second rule' refers to:",
        options = {
            a = "How long you have to run a yellow light",
            b = "The minimum following distance in good conditions",
            c = "How quickly you should shift gears",
            d = "The time it takes to parallel park a Benson"
        },
        correct = 'b'
    },
    -- 8
    {
        question = "You notice a tire is significantly underinflated during your pre-trip inspection. What should you do?",
        options = {
            a = "Drive slowly and hope for the best",
            b = "Do not drive the vehicle until the tire is properly inflated or replaced",
            c = "Kick it a few times to see if it feels okay",
            d = "Only worry about it if it's a front tire"
        },
        correct = 'b'
    },
    -- 9
    {
        question = "Hydroplaning is most likely to occur when:",
        options = {
            a = "You drive through a car wash",
            b = "In the first 10-15 minutes of light rain when oil and water mix on the road",
            c = "Only during hurricanes",
            d = "You are driving uphill on dry pavement"
        },
        correct = 'b'
    },
    -- 10
    {
        question = "What is the purpose of retarders (engine brakes / jake brakes) on a commercial vehicle?",
        options = {
            a = "To make the truck louder so people know you're cool",
            b = "To help slow the vehicle and reduce wear on service brakes",
            c = "To increase fuel efficiency on flat roads",
            d = "To warm up the engine in cold weather"
        },
        correct = 'b'
    },
    -- 11
    {
        question = "During a vehicle inspection, you find a cracked windshield that impairs your vision. Should you drive the vehicle?",
        options = {
            a = "Yes, just lean to the side to see around the crack",
            b = "Yes, as long as it's not raining",
            c = "No, the vehicle should not be driven until the windshield is repaired or replaced",
            d = "Yes, but only on highways where there's less to look at"
        },
        correct = 'c'
    },
    -- 12
    {
        question = "When making a right turn in a box truck, you should be especially careful about:",
        options = {
            a = "Your truck's off-tracking, which can cause the rear wheels to run over the curb",
            b = "Using your turn signal too early",
            c = "Turning the radio down",
            d = "Making sure your coffee doesn't spill"
        },
        correct = 'a'
    },
    -- 13
    {
        question = "What does GVWR stand for?",
        options = {
            a = "Great Vehicles With Refrigeration",
            b = "Gross Vehicle Weight Rating",
            c = "General Vehicle Width Requirement",
            d = "Government Vehicle Warranty Registration"
        },
        correct = 'b'
    },
    -- 14
    {
        question = "If your vehicle starts to skid, you should:",
        options = {
            a = "Slam on the brakes as hard as possible",
            b = "Turn the wheel sharply in the opposite direction of the skid",
            c = "Stop braking, steer in the direction you want to go, and countersteer as needed",
            d = "Accelerate to power through the skid"
        },
        correct = 'c'
    },
    -- 15
    {
        question = "You're hauling cargo in your Benson. How often should you check your cargo securement after beginning a trip?",
        options = {
            a = "Only if you hear something fall",
            b = "Within the first 50 miles, then every 150 miles or 3 hours",
            c = "Once a week",
            d = "Never, the loading dock handles all that"
        },
        correct = 'b'
    },
    -- 16
    {
        question = "Which of the following is a sign that your brakes may need adjustment?",
        options = {
            a = "The truck stops normally",
            b = "The brake pedal feels soft or goes to the floor",
            c = "The radio reception improves",
            d = "The steering wheel vibrates at highway speed"
        },
        correct = 'b'
    },
    -- 17
    {
        question = "What is the primary danger of driving a tall box truck like the Benson under low bridges?",
        options = {
            a = "The bridge might collapse from your awesomeness",
            b = "Striking the bridge, causing damage to the vehicle, cargo, and potentially the bridge",
            c = "Tall trucks get better fuel economy under bridges",
            d = "Low bridges are always on one-way streets"
        },
        correct = 'b'
    },
    -- 18
    {
        question = "The 'No Zone' refers to:",
        options = {
            a = "A speed limit zone near schools",
            b = "Areas around a commercial vehicle where other vehicles disappear into blind spots",
            c = "Zones where trucks are not allowed to park",
            d = "The area behind the rear bumper only"
        },
        correct = 'b'
    },
    -- 19
    {
        question = "When should you use your high beams while driving a commercial vehicle at night?",
        options = {
            a = "Always, because you're the biggest vehicle on the road",
            b = "When there is no oncoming traffic and you're not following another vehicle closely",
            c = "Never, commercial vehicles are not allowed to use high beams",
            d = "Only when driving through tunnels"
        },
        correct = 'b'
    },
    -- 20
    {
        question = "What should you do if you experience a tire blowout on the highway?",
        options = {
            a = "Slam on the brakes immediately",
            b = "Hold the steering wheel firmly, stay off the brakes, and gradually slow down",
            c = "Swerve to the shoulder as fast as possible",
            d = "Speed up to get to a tire shop faster"
        },
        correct = 'b'
    },
    -- 21
    {
        question = "Which of the following fluids should you check during a pre-trip inspection?",
        options = {
            a = "Engine oil, coolant, power steering fluid, and windshield washer fluid",
            b = "Only engine oil",
            c = "Blinker fluid and muffler bearings",
            d = "Fluids don't need checking if the truck starts"
        },
        correct = 'a'
    },
    -- 22
    {
        question = "You're driving your Benson near the Del Perro Pier and a pedestrian steps into the crosswalk. What should you do?",
        options = {
            a = "Honk aggressively to assert dominance",
            b = "Speed up to clear the intersection before they cross",
            c = "Yield to the pedestrian and come to a complete stop",
            d = "Flash your lights to confuse them"
        },
        correct = 'c'
    },
    -- 23
    {
        question = "What is the main purpose of the vehicle's exhaust system in the context of a pre-trip inspection?",
        options = {
            a = "To make the truck sound intimidating",
            b = "To safely route exhaust gases away from the cab and prevent carbon monoxide exposure",
            c = "To provide extra horsepower",
            d = "It's purely decorative"
        },
        correct = 'b'
    },
    -- 24
    {
        question = "A commercial vehicle's horn should be used:",
        options = {
            a = "To greet other truckers because you're lonely",
            b = "Only to warn others of danger or your presence when necessary",
            c = "Constantly in traffic to move things along",
            d = "As a substitute for turn signals"
        },
        correct = 'b'
    },
    -- 25
    {
        question = "The minimum tread depth for front tires on a commercial vehicle is:",
        options = {
            a = "4/32 of an inch",
            b = "2/32 of an inch, same as passenger cars",
            c = "Whatever looks good enough",
            d = "There is no minimum as long as there's some rubber left"
        },
        correct = 'a'
    },
    -- 26
    {
        question = "When backing a box truck, the safest practice is to:",
        options = {
            a = "Back up as quickly as possible to get it over with",
            b = "Use a spotter, back slowly, and use mirrors on both sides",
            c = "Only use the driver's side mirror",
            d = "Honk the horn continuously while backing"
        },
        correct = 'b'
    },
    -- 27
    {
        question = "Overloading your Benson beyond its GVWR can result in:",
        options = {
            a = "Better traction in wet conditions",
            b = "Brake failure, tire blowouts, structural damage, and loss of vehicle control",
            c = "Improved fuel economy due to momentum",
            d = "Nothing, trucks are built to handle anything"
        },
        correct = 'b'
    },
    -- 28
    {
        question = "When is it acceptable to leave your commercial vehicle unattended with the engine running?",
        options = {
            a = "When you're just grabbing a quick coffee at the gas station",
            b = "It is generally not acceptable; you should turn off the engine and secure the vehicle",
            c = "Whenever the keys are hidden under the seat",
            d = "Only on Tuesdays"
        },
        correct = 'b'
    },
    -- 29
    {
        question = "What does a flashing amber light on an emergency vehicle ahead typically mean?",
        options = {
            a = "Speed up and pass them",
            b = "Caution — slow down, move over if possible, and proceed carefully",
            c = "The vehicle is broken down and you should ignore it",
            d = "It's a disco party you weren't invited to"
        },
        correct = 'b'
    },
    -- 30
    {
        question = "Which of the following is the best way to check for proper brake function during a pre-trip?",
        options = {
            a = "Listen for grinding sounds while driving at highway speed",
            b = "With the vehicle at low speed, apply the brakes firmly to test for pull, grab, or delay",
            c = "Just assume they work if the pedal isn't on the floor",
            d = "Ask the last driver if they had any issues"
        },
        correct = 'b'
    },
    -- 31
    {
        question = "When driving in heavy fog, you should:",
        options = {
            a = "Use high beams to see further ahead",
            b = "Use low beams, reduce speed, and increase following distance",
            c = "Turn off all lights to avoid reflecting off the fog",
            d = "Follow the taillights of the car ahead as closely as possible"
        },
        correct = 'b'
    },
    -- 32
    {
        question = "You're approaching a railroad crossing with no signals in your Benson. What should you do?",
        options = {
            a = "Speed up to cross quickly before any train arrives",
            b = "Stop, look both ways, listen, and proceed only when safe",
            c = "Honk your horn to warn the train",
            d = "Railroad crossings without signals don't exist"
        },
        correct = 'b'
    },
    -- 33
    {
        question = "What is the purpose of safety/emergency triangles (reflective triangles)?",
        options = {
            a = "They make your truck look more professional",
            b = "To warn approaching traffic of a stopped vehicle, placed within 10 minutes of stopping",
            c = "They're only required in the rain",
            d = "To mark your territory at truck stops"
        },
        correct = 'b'
    },
    -- 34
    {
        question = "If you must drive through a deep puddle, what should you do afterward?",
        options = {
            a = "Nothing, water is good for brakes",
            b = "Lightly apply brakes to dry them and restore braking ability",
            c = "Turn up the heater to dry the truck",
            d = "Speed up to blow-dry the undercarriage"
        },
        correct = 'b'
    },
    -- 35
    {
        question = "What is the legal blood alcohol concentration (BAC) limit for commercial vehicle drivers?",
        options = {
            a = "0.08%, same as everyone else",
            b = "0.04%, half the limit for non-commercial drivers",
            c = "0.00%, absolutely no alcohol ever in your life",
            d = "0.10%, because truckers can handle it"
        },
        correct = 'b'
    },
    -- 36
    {
        question = "Properly secured cargo should be checked to ensure it:",
        options = {
            a = "Looks aesthetically pleasing in the mirror",
            b = "Cannot shift, fall, or leak during transport",
            c = "Is stacked as high as possible for efficiency",
            d = "Is only secured on the driver's side"
        },
        correct = 'b'
    },
    -- 37
    {
        question = "When merging onto the highway in a loaded Benson, you should:",
        options = {
            a = "Merge at the same speed as highway traffic, using the full acceleration lane",
            b = "Stop at the end of the ramp and wait for a gap",
            c = "Merge at 25 mph because you're big and everyone should yield to you",
            d = "Close your eyes and merge on faith"
        },
        correct = 'a'
    },
    -- 38
    {
        question = "Which mirror check is most important when changing lanes to the right?",
        options = {
            a = "Only the rearview mirror",
            b = "The right-side convex mirror to check the blind spot area",
            c = "No mirror — just use your gut feeling",
            d = "The left-side mirror, obviously"
        },
        correct = 'b'
    },
    -- 39
    {
        question = "A driver who holds a Class B CDL is permitted to operate which of the following?",
        options = {
            a = "Any tractor-trailer combination",
            b = "Single vehicles with a GVWR of 26,001 lbs or more, and tow vehicles under 10,000 lbs GVWR",
            c = "Motorcycles and passenger vehicles only",
            d = "Military tanks and fighter jets"
        },
        correct = 'b'
    },
    -- 40
    {
        question = "You've just finished a delivery in Paleto Bay and need to drive back empty. How does an empty truck handle differently?",
        options = {
            a = "It handles exactly the same, weight doesn't matter",
            b = "An empty truck is lighter, has less traction, bounces more, and can be harder to stop safely",
            c = "Empty trucks corner better because they weigh less",
            d = "Empty trucks use more fuel so you should load up with rocks"
        },
        correct = 'b'
    }
}

-- =============================================================================
-- CLASS A — 40 Questions
-- Advanced topics: combination vehicles, air brakes, coupling/uncoupling,
-- advanced backing, Class A specific. For the full CDL (tractor-trailers
-- like the Phantom, Hauler, etc.)
-- =============================================================================
CDLQuestionPools.class_a = {
    -- 1
    {
        question = "When coupling a tractor to a trailer, what should you do BEFORE backing under the trailer?",
        options = {
            a = "Say a little prayer and hope the fifth wheel lines up",
            b = "Inspect the fifth wheel, ensure it is greased, tilted, and the jaws are open",
            c = "Accelerate quickly so the kingpin hits hard and locks in place",
            d = "Have a spotter push the trailer toward you"
        },
        correct = 'b'
    },
    -- 2
    {
        question = "The fifth wheel on a tractor is designed to:",
        options = {
            a = "Hold your spare tire",
            b = "Connect the tractor to the trailer via the trailer's kingpin",
            c = "Provide extra steering at low speeds",
            d = "Act as a speed bump for the trailer"
        },
        correct = 'b'
    },
    -- 3
    {
        question = "After coupling your Phantom to a trailer, you perform a tug test. What are you checking?",
        options = {
            a = "Whether the tractor has enough power to pull the load",
            b = "That the fifth wheel jaws have properly locked around the kingpin",
            c = "How loud the engine sounds under strain",
            d = "If the trailer brakes are working"
        },
        correct = 'b'
    },
    -- 4
    {
        question = "What is 'trailer swing' and when does it occur?",
        options = {
            a = "When your trailer dances in the wind on the highway",
            b = "The rear of the trailer swinging outward during a tight turn, potentially striking objects",
            c = "A popular trucker dance move at rest stops",
            d = "When the trailer sways due to overinflated tires"
        },
        correct = 'b'
    },
    -- 5
    {
        question = "In an air brake system, the air compressor is driven by:",
        options = {
            a = "A hamster on a wheel under the hood",
            b = "The vehicle's engine through gears or a belt",
            c = "A separate battery-powered motor",
            d = "Wind resistance while driving"
        },
        correct = 'b'
    },
    -- 6
    {
        question = "The air brake system's governor controls:",
        options = {
            a = "The speed of the vehicle on downgrades",
            b = "When the air compressor pumps air into the storage tanks, typically cutting in around 100 psi and cutting out around 125 psi",
            c = "The amount of fuel injected into the engine",
            d = "The stereo volume based on engine noise"
        },
        correct = 'b'
    },
    -- 7
    {
        question = "What is the purpose of the air brake system's safety valve?",
        options = {
            a = "To keep the cab smelling fresh",
            b = "To protect the tank from exceeding safe pressure levels by releasing excess air",
            c = "To add more air when pressure is low",
            d = "To blow the horn automatically in emergencies"
        },
        correct = 'b'
    },
    -- 8
    {
        question = "During an air brake check, the low-pressure warning signal should activate before air pressure drops below:",
        options = {
            a = "100 psi",
            b = "60 psi",
            c = "30 psi",
            d = "10 psi, also known as 'you're already dead'"
        },
        correct = 'b'
    },
    -- 9
    {
        question = "What are spring brakes?",
        options = {
            a = "Brakes that only work during springtime",
            b = "Brakes that apply automatically when air pressure drops too low, using mechanical spring force",
            c = "Lightweight brakes made from spring steel",
            d = "Extra brakes installed for bouncy roads"
        },
        correct = 'b'
    },
    -- 10
    {
        question = "What is 'brake lag' in an air brake system?",
        options = {
            a = "The hesitation you feel before pressing the brake pedal",
            b = "The delay between pressing the brake pedal and the brakes actually engaging, due to air travel time",
            c = "When your brakes work on a delay from yesterday",
            d = "Lag caused by using cruise control"
        },
        correct = 'b'
    },
    -- 11
    {
        question = "You're performing an air brake leak test. With the engine off and brakes released, the air pressure should not drop more than:",
        options = {
            a = "3 psi in one minute for a combination vehicle",
            b = "20 psi in one minute",
            c = "Any drop means immediate failure",
            d = "There is no acceptable leak rate"
        },
        correct = 'a'
    },
    -- 12
    {
        question = "When uncoupling a trailer, what should you do BEFORE disconnecting the air and electrical lines?",
        options = {
            a = "Drive forward at full speed to yank them off",
            b = "Chock the trailer wheels and lower the landing gear",
            c = "Wave goodbye to the trailer",
            d = "Disconnect the fifth wheel release first"
        },
        correct = 'b'
    },
    -- 13
    {
        question = "A 'jackknife' occurs when:",
        options = {
            a = "You unfold a knife in the cab to cut your sandwich",
            b = "The drive wheels lose traction and the trailer pushes the tractor, causing it to swing sideways",
            c = "You make a perfect 90-degree turn",
            d = "The trailer disconnects from the tractor"
        },
        correct = 'b'
    },
    -- 14
    {
        question = "To help prevent a jackknife, you should:",
        options = {
            a = "Always brake as hard as possible in turns",
            b = "Avoid sudden braking and steering maneuvers, especially on slippery surfaces",
            c = "Speed up through turns to maintain momentum",
            d = "Keep your trailer empty at all times"
        },
        correct = 'b'
    },
    -- 15
    {
        question = "When backing a tractor-trailer to the left (driver side), you should turn the steering wheel:",
        options = {
            a = "To the right, because everything is opposite with trailers",
            b = "To the left — the trailer will go left when you steer left in a driver-side back",
            c = "Straight — let the trailer figure it out",
            d = "It doesn't matter, just send it"
        },
        correct = 'b'
    },
    -- 16
    {
        question = "Why is a 'blind-side' back (backing to the right) more dangerous?",
        options = {
            a = "The right side of the truck is cursed",
            b = "You cannot see the trailer's path as well since you must rely on mirrors instead of looking out the window",
            c = "The steering is reversed on the right side",
            d = "Right-side backs aren't more dangerous; that's a myth"
        },
        correct = 'b'
    },
    -- 17
    {
        question = "The air brake system's dual air brake system has two separate air systems. Why?",
        options = {
            a = "One for the radio and one for the brakes",
            b = "So if one system fails, the other can still provide braking on some wheels",
            c = "One is for summer and one is for winter",
            d = "It's a redundant design flaw from the 1950s"
        },
        correct = 'b'
    },
    -- 18
    {
        question = "What is the purpose of an alcohol evaporator in an air brake system?",
        options = {
            a = "To remove alcohol from the driver's breath before DOT stops",
            b = "To help prevent ice from forming in the air brake valves and lines in cold weather",
            c = "To convert air into alcohol for the air dryer",
            d = "To make the brakes smell better"
        },
        correct = 'b'
    },
    -- 19
    {
        question = "When coupling, you should connect the air lines by:",
        options = {
            a = "Smashing the glad hands together as hard as possible",
            b = "Matching the service (blue) and emergency (red) glad hands to the correct connections and securing them",
            c = "Connecting only the emergency line; the service line is optional",
            d = "Using duct tape if the glad hands don't fit"
        },
        correct = 'b'
    },
    -- 20
    {
        question = "If you cross-connect the air lines (swap the service and emergency lines), what happens?",
        options = {
            a = "Nothing, they're interchangeable",
            b = "The trailer brakes could release when you press the pedal and lock up when you release it",
            c = "The trailer gets extra braking power",
            d = "An alarm sounds to warn you"
        },
        correct = 'b'
    },
    -- 21
    {
        question = "What is 'off-tracking' in a combination vehicle?",
        options = {
            a = "When your GPS sends you down the wrong road",
            b = "When the rear wheels of the trailer follow a shorter path than the tractor's front wheels during a turn",
            c = "When the truck drifts off the road due to wind",
            d = "Driving off-road for a shortcut"
        },
        correct = 'b'
    },
    -- 22
    {
        question = "You're hooking your Hauler to a flatbed at the Los Santos docks. The trailer is too low for the fifth wheel. What should you do?",
        options = {
            a = "Ram under it anyway; force solves everything",
            b = "Use the trailer's landing gear to raise it to the correct height before backing under",
            c = "Let the air out of the tractor's tires to lower it",
            d = "Find a smaller tractor"
        },
        correct = 'b'
    },
    -- 23
    {
        question = "When checking the air brake system, you should build air pressure to the governor cut-out. The cut-out should occur at approximately:",
        options = {
            a = "50-75 psi",
            b = "120-145 psi",
            c = "200 psi",
            d = "It should never cut out; constant air is better"
        },
        correct = 'b'
    },
    -- 24
    {
        question = "A Class A CDL allows you to operate:",
        options = {
            a = "Only single vehicles over 26,001 lbs GVWR",
            b = "Combination vehicles where the GCWR is 26,001 lbs or more AND the towed vehicle is over 10,000 lbs GVWR",
            c = "Any vehicle regardless of weight",
            d = "Only vehicles with automatic transmissions"
        },
        correct = 'b'
    },
    -- 25
    {
        question = "During the straight-line backing test, you should use which technique?",
        options = {
            a = "Floor it in reverse and hope for the best",
            b = "Back slowly, make small steering corrections early, and use both mirrors",
            c = "Only look in the left mirror",
            d = "Turn the wheel all the way to one side for stability"
        },
        correct = 'b'
    },
    -- 26
    {
        question = "The trailer hand valve (trolley valve) should be used for:",
        options = {
            a = "Parking on hills permanently",
            b = "Testing the trailer brakes; it should never be used for parking",
            c = "Replacing the foot brake entirely",
            d = "Making the trailer brakes screech impressively"
        },
        correct = 'b'
    },
    -- 27
    {
        question = "What happens if you don't raise the landing gear fully after coupling?",
        options = {
            a = "Better aerodynamics because the legs act as wings",
            b = "The landing gear can snag on railroad tracks, speed bumps, or uneven road surfaces",
            c = "Nothing, they retract automatically at speed",
            d = "The trailer will steer more easily"
        },
        correct = 'b'
    },
    -- 28
    {
        question = "When driving a combination vehicle in strong crosswinds on the Great Ocean Highway, you should:",
        options = {
            a = "Drive faster to push through the wind",
            b = "Reduce speed, keep a firm grip on the wheel, and be especially cautious with an empty or lightly loaded trailer",
            c = "Open all windows to equalize pressure",
            d = "Draft behind another large truck for wind protection"
        },
        correct = 'b'
    },
    -- 29
    {
        question = "What is the most common cause of combination vehicle rollovers?",
        options = {
            a = "Mechanical failures",
            b = "Excessive speed in turns and curves",
            c = "Other drivers cutting them off",
            d = "Driving with the windows down"
        },
        correct = 'b'
    },
    -- 30
    {
        question = "Glad hands are:",
        options = {
            a = "The trucker's term for a friendly wave",
            b = "The coupling devices that connect the tractor's air lines to the trailer's air lines",
            c = "Gloves worn during vehicle inspection",
            d = "Rubber grips on the steering wheel"
        },
        correct = 'b'
    },
    -- 31
    {
        question = "When should you use the parking brake on a combination vehicle?",
        options = {
            a = "Only when parking on steep hills",
            b = "Every time you park the vehicle, regardless of grade or surface",
            c = "Never — just leave it in gear",
            d = "Only when sleeping in the cab"
        },
        correct = 'b'
    },
    -- 32
    {
        question = "S-cam brakes are the most common type of air brake. The S-cam works by:",
        options = {
            a = "Shooting brake fluid at the drums at high pressure",
            b = "Turning and pushing the brake shoes outward against the brake drum",
            c = "Pulling the brake pads inward like a disc brake",
            d = "Inflating an airbag inside the drum"
        },
        correct = 'b'
    },
    -- 33
    {
        question = "What should you check when inspecting the coupling area between the tractor and trailer?",
        options = {
            a = "Only that it looks connected from the cab",
            b = "Fifth wheel locking jaws closed around kingpin, no space between upper and lower fifth wheel, locking lever in place, safety latch engaged",
            c = "Just the air lines",
            d = "The paint job on the kingpin"
        },
        correct = 'b'
    },
    -- 34
    {
        question = "If your Phantom's trailer starts to sway on the highway, you should:",
        options = {
            a = "Steer sharply to counteract the sway",
            b = "Take your foot off the accelerator and avoid braking harshly; let the vehicle slow gradually",
            c = "Accelerate to straighten the trailer out",
            d = "Immediately pull the trailer hand valve"
        },
        correct = 'b'
    },
    -- 35
    {
        question = "The total stopping distance for a combination vehicle with air brakes is longer than hydraulic brakes because:",
        options = {
            a = "Truckers have slower reflexes than car drivers",
            b = "Air brake lag adds an additional delay before the brakes fully engage",
            c = "The tires are made of softer rubber",
            d = "Combination vehicles are painted darker colors"
        },
        correct = 'b'
    },
    -- 36
    {
        question = "When performing a 90-degree alley dock back with a tractor-trailer, you should begin by:",
        options = {
            a = "Turning the wheel hard and flooring the reverse",
            b = "Pulling past the alley, positioning the tractor, then slowly backing while adjusting the trailer angle",
            c = "Disconnecting the trailer and pushing it in by hand",
            d = "Asking someone else to do it because it's too hard"
        },
        correct = 'b'
    },
    -- 37
    {
        question = "The air compressor should build air pressure from 85 to 100 psi within approximately:",
        options = {
            a = "45 seconds",
            b = "2 minutes or less",
            c = "10 minutes",
            d = "However long it takes; there's no standard"
        },
        correct = 'a'
    },
    -- 38
    {
        question = "What is the maximum air loss rate for a combination vehicle with the engine off and brakes applied?",
        options = {
            a = "1 psi per minute",
            b = "4 psi in one minute",
            c = "10 psi in one minute",
            d = "Any amount is acceptable as long as the brakes hold"
        },
        correct = 'b'
    },
    -- 39
    {
        question = "You notice oil on the fifth wheel plate. This means:",
        options = {
            a = "Someone spilled their lunch",
            b = "It is properly greased, which is correct — the fifth wheel needs lubrication to allow the trailer to pivot smoothly",
            c = "There's a serious oil leak from the engine",
            d = "The kingpin is worn out and needs replacement"
        },
        correct = 'b'
    },
    -- 40
    {
        question = "When driving a tractor-trailer downhill on Route 68, you should select a gear that allows you to:",
        options = {
            a = "Coast in neutral to save fuel",
            b = "Control your speed without relying heavily on the service brakes, using engine braking as the primary retarder",
            c = "Maintain the speed limit in the highest gear possible",
            d = "Shift into reverse if you need to slow down"
        },
        correct = 'b'
    }
}

-- =============================================================================
-- TANKER — 15 Questions
-- Tanker endorsement: liquid surge, baffles, loading/unloading, rollover
-- prevention, pressure/vacuum, hazmat overlap for fuel hauling.
-- =============================================================================
CDLQuestionPools.tanker = {
    -- 1
    {
        question = "Liquid surge occurs in tanker vehicles when:",
        options = {
            a = "You add too much sugar to your coffee while driving",
            b = "The liquid inside a partially filled tank moves back and forth or side to side during braking, acceleration, or turning",
            c = "The liquid evaporates and creates pressure",
            d = "Rain hits the outside of the tank"
        },
        correct = 'b'
    },
    -- 2
    {
        question = "What is the primary purpose of baffles inside a tanker?",
        options = {
            a = "To make the liquid taste better",
            b = "To reduce the front-to-back surge of liquid by breaking the tank into sections with holes",
            c = "To prevent the tank from rusting",
            d = "To separate different types of fuel"
        },
        correct = 'b'
    },
    -- 3
    {
        question = "A tanker without baffles (a smooth bore tank) is typically used for:",
        options = {
            a = "Maximum surge because the driver enjoys a challenge",
            b = "Transporting food-grade products like milk, where internal surfaces must be easily sanitized",
            c = "Hauling solid cargo disguised as liquid",
            d = "Racing, because smooth bore tanks are faster"
        },
        correct = 'b'
    },
    -- 4
    {
        question = "Why are partially loaded tankers more dangerous than fully loaded ones?",
        options = {
            a = "They weigh less, so they have less traction",
            b = "The empty space allows the liquid to slosh and surge, shifting the center of gravity unpredictably",
            c = "The extra air in the tank can explode",
            d = "They aren't; partially loaded is always safer"
        },
        correct = 'b'
    },
    -- 5
    {
        question = "When hauling fuel through Sandy Shores, you approach a sharp curve. Compared to a dry van, you should:",
        options = {
            a = "Take it at the same speed — liquid doesn't affect handling",
            b = "Slow down significantly more, as the liquid load shifts toward the outside of the curve, raising rollover risk",
            c = "Speed up so centrifugal force pushes the liquid to the bottom of the tank",
            d = "Drain some fuel to lighten the load before the curve"
        },
        correct = 'b'
    },
    -- 6
    {
        question = "What should you do before loading or unloading a fuel tanker?",
        options = {
            a = "Light a cigarette to calm your nerves",
            b = "Ground the tanker to prevent static discharge, chock the wheels, and verify the correct product",
            c = "Rev the engine to maintain air pressure",
            d = "Open all the valves at once to save time"
        },
        correct = 'b'
    },
    -- 7
    {
        question = "Tanker vehicles have a higher center of gravity than most trucks. This means:",
        options = {
            a = "They're harder to see from the ground",
            b = "They are more susceptible to rollovers, especially on curves, ramps, and during evasive maneuvers",
            c = "They get better gas mileage due to aerodynamics",
            d = "They handle better in the wind"
        },
        correct = 'b'
    },
    -- 8
    {
        question = "The outage allowance (ullage) when loading a tanker refers to:",
        options = {
            a = "The amount of fuel you spill during loading",
            b = "The space left in the tank to allow for liquid expansion due to temperature changes",
            c = "The discount you get for buying fuel in bulk",
            d = "The amount of air needed for the liquid to breathe"
        },
        correct = 'b'
    },
    -- 9
    {
        question = "When stopping a tanker at a traffic light, you should leave extra following distance because:",
        options = {
            a = "You need more room for your ego",
            b = "After you stop, the liquid surge can push the truck forward into the intersection",
            c = "Tankers are slower to accelerate from a stop",
            d = "Traffic lights are spaced further apart for tankers"
        },
        correct = 'b'
    },
    -- 10
    {
        question = "Which endorsement is required on your CDL to drive a tanker carrying gasoline?",
        options = {
            a = "N endorsement (Tanker) only",
            b = "Both N (Tanker) and H (Hazardous Materials) endorsements, which combined form the X endorsement",
            c = "Only the H endorsement, since gasoline is hazmat",
            d = "No special endorsement — Class A covers everything"
        },
        correct = 'b'
    },
    -- 11
    {
        question = "Emergency shutoff valves on a fuel tanker should be:",
        options = {
            a = "Painted bright colors for aesthetic purposes",
            b = "Checked during pre-trip to ensure they work and close properly to stop the flow of product in an emergency",
            c = "Left open during transport for ventilation",
            d = "Removed if the tanker is less than five years old"
        },
        correct = 'b'
    },
    -- 12
    {
        question = "If you are hauling fuel and notice a leak from your tanker, you should:",
        options = {
            a = "Drive faster to get to the delivery point before you lose too much product",
            b = "Stop in a safe location away from traffic and ignition sources, secure the area, and report the leak immediately",
            c = "Plug the leak with a rag and keep driving",
            d = "Ignore small leaks; they're normal"
        },
        correct = 'b'
    },
    -- 13
    {
        question = "Rollover risk in a tanker is highest when:",
        options = {
            a = "Driving straight on a flat highway",
            b = "Turning, taking curves too fast, or making sudden lane changes, especially when the tank is partially full",
            c = "Parked at a fuel station",
            d = "Driving slowly in a straight line uphill"
        },
        correct = 'b'
    },
    -- 14
    {
        question = "Bulkheads inside a tanker differ from baffles because:",
        options = {
            a = "Bulkheads are decorative and baffles are functional",
            b = "Bulkheads completely divide the tank into separate compartments with no holes, while baffles have openings for liquid flow",
            c = "They're the same thing, just different names",
            d = "Bulkheads are on the outside of the tank"
        },
        correct = 'b'
    },
    -- 15
    {
        question = "When driving a tanker down the Senora Freeway and you need to change lanes, the best practice is to:",
        options = {
            a = "Whip the steering wheel quickly to get it over with",
            b = "Signal early, check mirrors, and change lanes slowly and smoothly to minimize liquid surge and maintain vehicle stability",
            c = "Change multiple lanes at once to reduce the total number of lane changes",
            d = "Only change lanes on straightaways at maximum speed"
        },
        correct = 'b'
    }
}
