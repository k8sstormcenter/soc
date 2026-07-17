#!/bin/bash
#comment one set of the two blocks
docker tag entlein/poc:good0.0.2 entlein/poc:0.0.2
docker push entlein/poc:0.0.2
docker tag entlein/poc:good0.0.2 entlein/poc:0.0.9
docker push entlein/poc:0.0.9
docker tag entlein/poc:good0.0.2 entlein/poc:0.0.8
docker push entlein/poc:0.0.8

#docker tag entlein/poc:bad0.0.2 entlein/poc:0.0.2
#docker push entlein/poc:0.0.2
#docker tag entlein/poc:bad0.0.9 entlein/poc:0.0.9
#docker push entlein/poc:0.0.9
#docker tag entlein/poc:bad0.0.8 entlein/poc:0.0.8
#docker push entlein/poc:0.0.8
