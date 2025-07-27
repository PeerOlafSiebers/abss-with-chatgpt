// gemma3_12b_itqat_0.6temp_40topk_0.8topp_latest_test_20250721-190342.json
model SubterraneanEcosystemSimulation

global {
	// Global variables
	float simulationTime <- 0.0;
	int initialPredatorPopulation <- 100;
	int initialPreyPopulation <- 500;
	int predatorPopulation <- initialPredatorPopulation;
	int preyPopulation <- initialPreyPopulation;
	int touristCount <- 20;
	int researcherCount <- 5;
	
	float mineralDepletionRate <- 1.0;
	string trailDensityString <- "Low";
	map trailDensityMapping <- ["Low"::1,"Moderate"::2,"High"::3]; 
	int trailDensity <- trailDensityMapping[trailDensityString];   // 1=Low, 2=Moderate, 3=High
    string visitorNoiseLevelString <- "Low";
    map visitorNoiseLevelMapping <- ["Low"::1,"Moderate"::2,"High"::3];
	int visitorNoiseLevel <- visitorNoiseLevelMapping[visitorNoiseLevelString];
	
	float disturbance <- (trailDensity * touristCount * visitorNoiseLevel) / 10.0;
	float predatorHuntingRate <- 0.5;
	float preyReproductionRate <- 0.2;
	
	float ecosystemResilienceIndex <- 1.0;

	reflex updateResilience {
		float biodiversity <- (predatorPopulation + preyPopulation) / (initialPredatorPopulation + initialPreyPopulation);
		float pressure <- 1.0 / (1.0 + disturbance);
		ecosystemResilienceIndex <- biodiversity * pressure;
	}

	init {
		create Predator number: initialPredatorPopulation;
		create Prey number: initialPreyPopulation;
	}

	// Global reflexes (methods from ArtificialLab) - Not implemented in this simplified model
	// reflex measurePopulationDynamics { ... }
	// reflex verifyHypothesis1 { ... }
	// reflex verifyHypothesis2 { ... }
}

species Predator {
	float energyLevel <- 50.0;
	float territorySize <- 10.0;
	int huntingFrequency <- 5;
	Cave cell_habitat <- one_of(Cave);

	reflex hunt {
		if (preyPopulation > 0) {
			Prey prey <- one_of(Prey where(location distance_to self.location <= territorySize));
			if (prey != nil) {
				ask prey {
					do die;
				}
				energyLevel <- energyLevel + 10;
				preyPopulation <- preyPopulation - 1;
			} else {
				energyLevel <- energyLevel - 5;
				do move;
			}
		} else {
			energyLevel <- energyLevel - 5;
		}
	}
	
	action move {
		// move to neighbor
		point newLocation <- one_of(self.location neighbors_at 1);
		self.location <- newLocation;
	}

	reflex defendTerritory {
		list<Predator> intruders <- Predator where (each != self and (each.location distance_to self.location) <= territorySize);
		if (!empty(intruders)) {
			Predator foe <- one_of(intruders);
			float myScore    <- rnd(10) + energyLevel;
         	float theirScore   <- rnd(10) + foe.energyLevel;
         	energyLevel <- energyLevel - 5;
         	if (myScore >= theirScore) { // win battle
         		ask foe {
         			energyLevel <- energyLevel - 20;
         			if (energyLevel <= 0) { do die; }
         		}
         	} else { // lost battle
         		energyLevel <- energyLevel - 15;
         	}
		}
	}
	
	reflex checkDie {
		if (energyLevel <= 0) {
			do die;
		}
		predatorPopulation <- length(Predator);
	}
	
	reflex noiseDisturbance {
      float loss <- visitorNoiseLevel * 0.02; // predators less sensitive to noise than prey
      energyLevel <- max(0, energyLevel - loss);
   }
	
	reflex reproduce {
		float rate <- 0.25;
		if (flip(rate) and energyLevel >= 10) {
			energyLevel <- energyLevel - 10;
			create Prey number: 1 returns: offspring;
			ask offspring {
				cell_habitat <- myself.cell_habitat;
			}
		}		
	}

	aspect base {
		draw circle(5) color: #red;
	}
}

species Prey {
	float energyLevel <- 30.0;
	string habitatPreference <- "Undergrowth";
	int riskAversion <- 3;
	Cave cell_habitat <- one_of(Cave);

	action evade {
		Predator nearest <- ( Predator sort_by (each distance_to(self.location)))[0];
		if (nearest distance_to self.location < 1 * riskAversion) {
			do move(nearest);
		}
	}
	
	reflex checkDie {
		if (energyLevel <= 0) {
			do die;
		}
		preyPopulation <- length(Prey);
	}
	
	reflex noiseDisturbance {
      float loss <- visitorNoiseLevel * 0.05;// 5 % of noise as energy loss
      energyLevel <- max(0, energyLevel - loss);
   }

	reflex forage {
		if (cell_habitat != nil and cell_habitat.hasMinerals and cell_habitat.mineralDeposit != nil and cell_habitat.mineralDeposit.amount >= mineralDepletionRate) {
			cell_habitat.mineralDeposit.amount <- cell_habitat.mineralDeposit.amount - mineralDepletionRate;
			energyLevel <- energyLevel + 5;
		} else {
			energyLevel <- energyLevel - 1;
		}
	}
	
	action move(Predator nearest) {
		// move to neighbor
		point newLocation <- (self.location neighbors_at 1 sort_by (-1 * (each distance_to(nearest.location))))[0];
		self.location <- newLocation; 
	}
	
	reflex reproduce {
		float rate <- 0.25;
		if (flip(rate) and energyLevel >= 10) {
			energyLevel <- energyLevel - 10;
			create Predator number: 3 returns: offspring;
			ask offspring {
				cell_habitat <- myself.cell_habitat;
			}
		}		
	}

	aspect base {
		draw circle(3) color: #green;
	}
}

species Tourist {
	float fatigueLevel <- 2.0;
	float satisfactionLevel <- 7.0;
	int wildlifeEncounterCount <- 0;

	action explore {
		wildlifeEncounterCount <- wildlifeEncounterCount + 1;
	}

	action respectWildlife {
		satisfactionLevel <- satisfactionLevel + 1;
	}

	aspect base {
		draw circle(3) color: #blue;
	}
}

species Researcher {
	float dataSufficiency <- 0.0;
	float measurementAccuracy <- 90.0;
	int analysisComplexity <- 2;

	action analyze {
		dataSufficiency <- dataSufficiency + 1;
	}

	action validate {
		measurementAccuracy <- measurementAccuracy + 1;
	}

	aspect base {
		draw circle(3) color: #yellow;
	}
}

grid Cave width: 100 height: 100 neighbors: 4 {
	bool hasMinerals <- false;
	MineralDeposit mineralDeposit <- nil;
	init {
		hasMinerals <- flip(0.3);
		if(hasMinerals) {
			create MineralDeposit number:1 returns: mineralDepositTemp;
			mineralDeposit <- mineralDepositTemp[0];
		}
	}
	reflex depleteMinerals {
		if(mineralDeposit != nil and mineralDeposit.amount <= 0) {
			ask mineralDeposit {
				do die;
			}
			hasMinerals <- false;
			mineralDeposit <- nil;
		}
	}
}

species MineralDeposit {
	float amount <- 10.0;
}

experiment EcosystemDynamics {
	parameter "mineralDepletionRate" var:mineralDepletionRate min: 0.1 max: 1.0 category: "continuous"; // this was mentioned to be both an {key-experimentalFactor} and {key-output}, I decided it to be a {key-experimentalFactor}.
	parameter "visitorNoiseLevel" var:visitorNoiseLevelString among: ["Low", "Moderate", "High"] category:"discrete";
	parameter "trailDensity" var:trailDensityString among:["Low", "Moderate", "High"] category:"discrete";

	output {
		// this is meant to be a mere representation (it is not part of {key-outputs}), hence it does not include trail etc.
		display EcosystemView refresh:every(5#cycles) {
			grid Cave border: #black;
			species Predator aspect: base;
			species Prey aspect: base;
			species Tourist aspect: base;
			species Researcher aspect: base;
		}
		display PopulationChart refresh:every(5#cycles) {
			chart "Population Chart" type: series {
				data "Predator Population" value: length(Predator);
				data "Prey Population" value: length(Prey);
			}
		}
		display ResilienceChart refresh:every(5#cycles) {
			chart "Ecosystem Resilience Index" type: series {
				data "ERI" value: ecosystemResilienceIndex;
			}
		}
	}
}