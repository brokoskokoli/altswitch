.PHONY: all build clean run

all: build

build:
	@chmod +x build.sh
	@./build.sh

clean:
	rm -rf .build/AltSwitch.app

run: build
	open .build/AltSwitch.app
