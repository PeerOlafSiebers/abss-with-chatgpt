// mistral-nemo_latest_test_20250721-203513.json
model VRAdoptionSimulation

global {
  // Global attributes
  float advertisingBudget <- 100000;

  // Global variables corresponding to parameters
  string advertisingStrategyString <- "Targeted";
  map advertisingStrategyMap -> ["TargetedAtEarlyAdopter"::3, "TargetedAtPotentialAdopter"::2, "TargetedAtPriceSensitive"::1, "MassMarket"::10];
  float advertisingStrategy <- advertisingStrategyMap[advertisingStrategyString];
  float pricePoint;
  float complementaryGoodsAvailability;

  int lastTotalSales<- 0;
  list<int> salesStepHistory <- [];	
  
  float marketPenetration   <- 0;
  float riskAdjustedReturn  <- 0;
  float inclusivityGap <- 0;
  
  reflex advertisingImpact {
  	// simulates advertising impact
    float intensity <- advertisingBudget * advertisingStrategy / 1e6;
    
    if (advertisingStrategyString = "TargetedAtEarlyAdopter") {
      loop a over: EarlyAdopter {
        a.engagementRate <- min(100, a.engagementRate + intensity);
      }
      
    } else if (advertisingStrategyString = "TargetedAtPotentialAdopter") {
      loop p over: PotentialAdopter {
        p.techSaviness <- min(5, p.techSaviness + intensity / 20);
      }
      
    } else if (advertisingStrategyString = "TargetedAtPriceSensitive") {
      loop s over: PriceSensitiveConsumer {
        s.savingsThreshold <- max(0.01, s.savingsThreshold - intensity/1000);
      }
    } else { /* MassMarket – broad, diluted boost */
      loop p over: PotentialAdopter     { p.techSaviness     <- min(5, p.techSaviness     + intensity/40); }
      loop s over: PriceSensitiveConsumer { s.savingsThreshold <- max(0.01, s.savingsThreshold - intensity/2000); }
      loop a over: EarlyAdopter         { a.engagementRate   <- min(100, a.engagementRate + intensity/2); }
    }
    }
  
  reflex updateMarketMetrics {
  	list<VRDevice> devices <- VRDevice;
  	list<PotentialAdopter> potentialAdopters <- PotentialAdopter;
  	list<PriceSensitiveConsumer> priceSensitiveConsumers <- PriceSensitiveConsumer;
  	int population  <- length(PotentialAdopter)+ length(PriceSensitiveConsumer)+ length(EarlyAdopter);
  	int totalSales   <- sum(devices collect each.sales);
  	marketPenetration <- (population = 0) ? 0 : (totalSales as float) / population;
  	
  	int stepSales <- totalSales - lastTotalSales;
  	salesStepHistory <- salesStepHistory + [stepSales];
  	lastTotalSales   <- totalSales;
  	
  	float revenue <- sum(devices collect (each.sales * each.pricePoint));
  	float cost <- (100000 - advertisingBudget);
  	float risk  <- (length(salesStepHistory) > 1) ? max(1, standard_deviation(salesStepHistory)):1;
  	riskAdjustedReturn <- (revenue - cost) / risk;
  	
  	list<float> budgets <- (potentialAdopters collect each.budgetAvailable) + (PriceSensitiveConsumer collect each.budgetAvailable);
  	float meanBudget <- empty(budgets) ? 0 : mean(budgets);
  	
  	list<PotentialAdopter> lowGroupPotential <- (potentialAdopters where (each.budgetAvailable <= meanBudget));
    list<PriceSensitiveConsumer> lowGroupSensitive <- (priceSensitiveConsumers where (each.budgetAvailable <= meanBudget));
    list<PotentialAdopter> highGroupPotential <- (potentialAdopters where (each.budgetAvailable > meanBudget));
    list<PriceSensitiveConsumer> highGroupSensitive <- (priceSensitiveConsumers where (each.budgetAvailable > meanBudget));
  	
  	float adoptLow <- ((length(lowGroupPotential) = 0) ? 0 : length(lowGroupPotential where each.ownsVR) / length(lowGroupPotential)) + ((length(lowGroupSensitive) = 0) ? 0 : length(lowGroupSensitive where each.ownsVR) / length(lowGroupSensitive));
    float adoptHigh <- ((length(highGroupPotential) = 0) ? 0 : length(highGroupPotential where each.ownsVR) / length(highGroupPotential)) + ((length(highGroupSensitive) = 0) ? 0 : length(highGroupSensitive where each.ownsVR) / length(highGroupSensitive));
    inclusivityGap <- adoptHigh - adoptLow; // positive ⇒ divide widens
  }

  init {
    // Create species
    create PotentialAdopter number: 1000;
    create EarlyAdopter number: 500;
    create PriceSensitiveConsumer number: 1500;
    create Influencer number: 200;

    // Initialize VRDevice and ComplementaryGood species
    create VRDevice number: 10;
    create ComplementaryGood number: 4;
    
    create VRExperience      number: 20;
  }
}

species PotentialAdopter {
  // Attributes
  string priceSensitivityIndexString;
  map priceSensitivityIndexMap -> ["Low"::1, "Medium"::2, "High"::3];
  int priceSensitivityIndex;
  float budgetAvailable;
  float techSaviness;
  
  bool ownsVR <- false;

  init {
    priceSensitivityIndexString <- one_of(["Low", "Medium", "High"]);
    priceSensitivityIndex <- priceSensitivityIndexMap[priceSensitivityIndexString];
    budgetAvailable <- rnd(0, 10000) * priceSensitivityIndex;
    techSaviness <- rnd(1, 5);
    ownsVR <- false;
  }

  reflex compareVRDevicePrices {
    list<VRDevice> devices <- VRDevice where (each.pricePoint <= budgetAvailable and each.featureComplexity <= techSaviness);
    if (!empty(devices)) {
    	loop device over: devices {
    		if(rnd(1,6) >= readVRDeviceReviews(device)) {
    			do purchaseVRDevice(device);
    			break;
    		}
    	}
    }
  }

  float readVRDeviceReviews(VRDevice device) {
    list<Review> reviews <- device.reviews;
    return mean(reviews collect each.rating);
  }

  action purchaseVRDevice(VRDevice device) {
    if(budgetAvailable >= device.pricePoint) {
      budgetAvailable <- budgetAvailable - device.pricePoint;
      device.sales <- device.sales + 1;
    }
    ownsVR <- true;
    do postPurchaseEvaluation(device);
  }

  action postPurchaseEvaluation(VRDevice device) {
  	create Review number: 1 returns: tempReviews;
  	Review tempReview <- tempReviews[0];
  	tempReview.rating <- rnd(1, 5);
  	tempReview.comment <- "";
    device.reviews <- device.reviews + [tempReview];
  }
}

species EarlyAdopter {
  // Attributes
  float socialMediaFollowing;
  float engagementRate;
  float techInnovationIndex;
  
  list<VRExperience> triedExperiences;
  list<VRExperience> sharedExperiences;
  
  list<PotentialAdopter> peerPotentials;
  list<PriceSensitiveConsumer> peerSensitives;
  list<EarlyAdopter> peerEarly;

  init {
    socialMediaFollowing <- rnd(0, 10000);
    engagementRate <- rnd(0, 50);
    techInnovationIndex <- rnd(1, 6);
    
    triedExperiences<- [];
    sharedExperiences <- [];
    
    int nPeers <- int(rnd(5, 15));
    peerPotentials <- shuffle(PotentialAdopter)[min(nPeers, length(PotentialAdopter))];
    peerSensitives <- [shuffle(PriceSensitiveConsumer), min(nPeers, length(PriceSensitiveConsumer))];
    peerEarly      <- [shuffle(EarlyAdopter where (each != self)),
                           min(nPeers, length(EarlyAdopter)-1)];
    
  }

  action exploreNewVRExperiences(VRExperience experience) {
  	list<VRExperience> candidates <- VRExperience where !(each in triedExperiences);
  	if (empty(candidates)) {
  		create VRExperience number:1 returns: newExp; 
  		add newExp to: candidates;
  	}
  	VRExperience exp <- one_of(candidates);
  	
  	techInnovationIndex <- techInnovationIndex + 0.05;
  	
  	// share probability grows with engagement rate
  	float pShare <- min(1.0, engagementRate / 100 + 0.2);
  	if (rnd(0,1) < pShare) {
  		do shareVRExperiencesOnSocialMedia(experience);
  	}
  	
  	add exp to: triedExperiences;
  	
  }

  action shareVRExperiencesOnSocialMedia(VRExperience experience) {
    sharedExperiences <- sharedExperiences + [experience];
    
    // engagement: followers * engagement rate * novelty boost
    bool firstPost <- !(experience in sharedExperiences);
    float noveltyBoost <- firstPost ? 1.2 : 1.0;
    float rawEngagement <- socialMediaFollowing * (engagementRate/100) * noveltyBoost* rnd(0.6, 1.4);
    float newFollowers <- rawEngagement / 20;
    socialMediaFollowing <- socialMediaFollowing + newFollowers;
    engagementRate <- (engagementRate * 4 + (rawEngagement / socialMediaFollowing) * 100) / 5;
    do influencePeers(experience);
  }

  action influencePeers(VRExperience experience) {
    float deltaTech   <- 0.01;
    loop p over: peerPotentials {
        p.techSaviness         <- min(5, p.techSaviness + deltaTech);
        p.priceSensitivityIndex <- max(1, p.priceSensitivityIndex - deltaTech * 2);
    }
  }
}

species PriceSensitiveConsumer {
  // Attributes
  float productPortfolioSize;
  float averagePricePoint;
  float marketShare;
  
  float budgetAvailable;
  
  float savingsThreshold;
  
  bool ownsVR;

  init {
    productPortfolioSize <- rnd(1, 1000);
    averagePricePoint <- rnd(0, 5000);
    marketShare <- rnd(0, 50);
    
    budgetAvailable <- rnd(200, 2000);
    
    savingsThreshold <- rnd(0.05, 0.25); // savings threshold wrt console
    ownsVR <- false;
  }
  
  map buildBundleCostMatrix { 
  	list<VRDevice> devs  <- VRDevice;
    list<ComplementaryGood> goods <- ComplementaryGood;
    int nR <- length(devs); // row in matrix
    int nC <- length(goods); // col in matrix
    matrix<float> cost <- matrix<float>(nR, nC, nil);
    loop i from: 0 to: nR - 1 {
    	VRDevice d <- devs[i];
        loop j from: 0 to: nC - 1 {
            ComplementaryGood g <- goods[j];

            if g.availability <= 0 { continue; }

            float total <- d.pricePoint + g.pricePoint;

            if total <= budgetAvailable {
            	write "* i = " + i + ", j = " + j + ". nr = " + nR + ", nC = " + nC + ". cost rows = " + cost.rows + ", cost cols = " + cost.columns;
                cost[point(i,j)] <- total;   // save the affordable bundle price
            }
        }
    }
    return ['matrix'::cost, 'devices'::devs, 'goods'::goods];
  }

  list<map> findAffordableVRBundles {
    list<map> bundles <- [];
    
    loop d over: VRDevice {
    	loop g over: ComplementaryGood {
    		if (g.availability <= 0) { continue; }
    		float total <- d.pricePoint + g.pricePoint;
    		if (total <= budgetAvailable) {
    			add ["device" :: d, "good" :: g, "total" :: total] to: bundles;
    		}
    	}
    }
    return bundles;
  }

  float compareVRDevicePricesWithGamingConsoles(VRDevice d) {
    float gamingConsolePrice <- retrieveGamingConsolePrice;
    float priceDifference <- abs(d.pricePoint - gamingConsolePrice);
    return priceDifference;
  }
  
  bool matrix_is_empty (matrix m) {
    loop i from: 0 to: m.rows - 1 {
        loop j from: 0 to: m.columns - 1 {
        	write "** i = " + i + ", j = " + j + ". m rows = " + m.rows + ", m cols = " + m.columns;
            if m[point(int(i),int(j))] != nil { return false; }
        }
    }
    return true;
	}

  action makePurchaseDecision {
    map result <- buildBundleCostMatrix();
    matrix<float> costs<- result['matrix'];
    list<VRDevice> devs <- result['devices'];
    list<ComplementaryGood> gs <- result['goods'];
    
    if matrix_is_empty(costs) { return; }
    
    float bestPrice <- nil;
    int bestI <- -1;
    int bestJ <- -1;
    
    loop i from: 0 to: costs.rows -1 {
        loop j from: 0 to: costs.columns - 1 {
        	write "*** i = " + i + ", j = " + j + ". cost rows = " + costs.rows + ", cost cols = " + costs.columns;
            float v <- costs[point(int(i),int(j))];
            if v = nil { continue; }

            if (bestPrice = nil) {
            	bestPrice <- v;
                bestI <- int(i); bestJ <- int(j);
            } else if (v < bestPrice) {
                bestPrice <- v;
                bestI <- int(i); bestJ <- int(j);
            }
        }
    }
    if bestPrice = nil { return; }
    VRDevice d <- devs[bestI];
    ComplementaryGood g <- gs[bestJ];
    
    budgetAvailable <- budgetAvailable - bestPrice;
    g.availability <- max(0, g.availability-1);
    d.sales<- d.sales + 1;
    do postPurchaseEvaluation(d);
  }
  
  float retrieveGamingConsolePrice {
      return rnd(300, 700);
  }
  
  action consoleComparisonShop {

      VRDevice cheapest <- first (VRDevice sort_by each.pricePoint);
      float consolePrice <- retrieveGamingConsolePrice;

      bool goodDeal <- cheapest.pricePoint <= consolePrice * (1 - savingsThreshold);

      if (goodDeal and cheapest.pricePoint <= budgetAvailable) {
          do purchaseVRDevice(cheapest);
      }
  }
  
  reflex bargainHunter {                      
      do makePurchaseDecision;                        
      if (budgetAvailable > 0) {
          do consoleComparisonShop;
      }
  }
  
  action purchaseVRDevice (VRDevice d) {
      if (budgetAvailable >= d.pricePoint) {
          budgetAvailable <- budgetAvailable - d.pricePoint;
          d.sales <- d.sales + 1;
          ownsVR <- true;
          do postPurchaseEvaluation(d);
      }
  }

  action postPurchaseEvaluation(VRDevice device) {
    create Review number: 1 returns: tempReviews;
  	Review tempReview <- tempReviews[0];
  	tempReview.rating <- rnd(1, 5);
  	tempReview.comment <- "";
    device.reviews <- device.reviews + [tempReview];
  }
}

species Influencer {
  // Attributes
  float communitySize;
  float influenceScore;
  float policyAlignmentIndex;
  
  list<PotentialAdopter> followerPotentials;
    list<PriceSensitiveConsumer> followerSensitives;
    list<EarlyAdopter>  followerEarly;
  list<VRDevice> sponsoredDevices;  // promoted so far

  init {
    communitySize <- rnd(1000, 100000);
    influenceScore <- rnd(0, 100);
    policyAlignmentIndex <- rnd(1, 6);
    
    int nFollowers <- int(rnd(100, 500));
    
    int nPot <- int(nFollowers * 0.5);
    int nSen <- int(nFollowers * 0.3);
    int nEar <- nFollowers - nPot - nSen;
    
    followerPotentials  <- shuffle(PotentialAdopter)[min(nPot, length(PotentialAdopter))];
    followerSensitives  <- shuffle(PriceSensitiveConsumer)[min(nSen, length(PriceSensitiveConsumer))];
    followerEarly       <- shuffle(EarlyAdopter)[min(nEar, length(EarlyAdopter))];
    sponsoredDevices <- [];
  }

  action collaborateWithVRManufacturers(VRManufacturer manufacturer) {
    VRDevice device <- one_of (VRDevice sort_by each.pricePoint);
    add device to: sponsoredDevices;
    
    float sponsorBoost <- rnd(0.05, 0.20);
    int newFollowers <- int(communitySize * sponsorBoost);
    communitySize <- communitySize + newFollowers;
    
    do reviewAndPromoteVRDevices(device);
  }

  action reviewAndPromoteVRDevices(VRDevice device) {
  	float meanReviewRating <- mean(device.reviews collect each.rating);
    float baseQuality <- empty(device.reviews) ? 3 : meanReviewRating;
    float quality <- (baseQuality + rnd(-1, 1)); 
    
    float engagement <- communitySize * (quality / 5) * rnd(0.6, 1.2);
    
    loop f over: followerPotentials {
    		f.priceSensitivityIndex <- max(1, f.priceSensitivityIndex - 0.1 * quality);
    		f.techSaviness <- min(5, f.techSaviness + 0.1 * quality);
    	}
    loop f over: followerSensitives {
    		f.savingsThreshold <- max(0.01, f.savingsThreshold - 0.02 * quality);
    	}
    influenceScore <- min(100, influenceScore + engagement / 10000);
  }
  
  // produce content from time to time
  reflex sponsoredContentClock {
  	if (rnd(0, 1) < 0.03) {
  		do collaborateWithVRManufacturers(one_of(VRManufacturer));
  	}
  }
}

species VRDevice {
  // Attributes
  float pricePoint;
  float featureComplexity;
  list<Review> reviews;
  int sales;

  init {
    pricePoint <- rnd(0, 5000);
    featureComplexity <- rnd(1,5);
    reviews <- [];
  }
}

species ComplementaryGood {
  // Attributes
  string productName;
  float pricePoint;
  float availability;

  init {
    productName <- "";
    pricePoint <- rnd(0, 1000);
    availability <- rnd(0, 100);
  }
}

species VRManufacturer {
  // Attributes
  string name;
  float pricePoint;

  init {
    name <- "";
    pricePoint <- rnd(0, 5000);
  }
}

species VRExperience {
  // Attributes
  string details;

  init {
    details <- ""; //not implemented due to time constraints (random string)
  }
}

species Review {
  // Attributes
  float rating;
  string comment;

  init {
    rating <- rnd(1, 6);
    comment <- "";
  }
}

experiment VRAdoptionExperiment {
  // Parameters
  parameter "advertisingStrategy" category: "advertising" var: advertisingStrategyString <- "Targeted" among:["TargetedAtEarlyAdopter", "TargetedAtPotentialAdopter", "TargetedAtPriceSensitive", "MassMarket"];
  parameter "pricePoint" var: pricePoint min: 0 max: 5000 category: "pricing";
  parameter "complementaryGoodsAvailability" var: complementaryGoodsAvailability min: 0 max: 100 category: "pricing";

  output {
  	display MarketDashboard {
  		chart "Market Penetration & Sales" type: series {
       data "Penetration" value: marketPenetration;
       data "Cumulative Sales" value: sum(VRDevice collect each.sales);
   }
  	}
  	display RiskAdjustedReturn {
	    chart "Risk-Adjusted Return" type: series {
	      data "RAR" value: riskAdjustedReturn;
	    }
	}
	
	  display InclusivityIndex {
	    chart "Inclusivity Index" type: series {
	      data "Adoption Gap (High – Low Income)" value: inclusivityGap;
	    }
	}
  }
}