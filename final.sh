awk -F, 'BEGIN {
        sex["M"] = "1:1 2:0 3:0";
        sex["F"] = "1:0 2:1 3:0";
        sex["I"] = "1:0 2:0 3:1";
        }
        {
        class = ($NF <= 9) ? -1 : 1;
        printf("%d %s", class, sex[$1]);
        for (i = 2; i <= NF - 1; ++i)
        printf(" %d:%s", i + 2, $i);
        printf("\n");
        }' data/abalone.data > data/dataset.txt

awk 'NR <= 3133 { print; }' data/dataset.txt > output/train.txt
awk 'NR > 3133 { print; }' data/dataset.txt  > output/test.txt


# Scale training and test set.                                                
libsvm_latest/svm-scale -s output/scale.txt output/train.txt > output/train.scaled.txt
libsvm_latest/svm-scale -r output/scale.txt output/test.txt > output/test.scaled.txt



sort -R output/train.scaled.txt > output/train.scaled.shuffled.txt
NUM_SAMPLES=$(cat output/train.scaled.shuffled.txt | wc --lines)
for SPLIT in $(seq 1 10); do
    awk "NR < $NUM_SAMPLES * ($SPLIT - 1) / 10.0 \
        || NR >= $NUM_SAMPLES * $SPLIT / 10.0" \
         output/train.scaled.shuffled.txt  > output/train.$SPLIT.txt
    awk "NR >= $NUM_SAMPLES * ($SPLIT - 1) / 10.0 \
        && NR < $NUM_SAMPLES * $SPLIT / 10.0" \
        output/train.scaled.shuffled.txt > output/dev.$SPLIT.txt
done
# Compute accuracy for diff

for LOG2C in $(seq -10 10); do
    for DEGREE in 1 2 3 4 5; do
        for SPLIT in $(seq 1 10); do
            C=$(python -c "print(3 ** $LOG2C)");
            echo "c="$C "d="$DEGREE "split="$SPLIT;
            libsvm_latest/svm-train -t 1 -d $DEGREE -c $C output/train.$SPLIT.txt output/model.$LOG2C.$DEGREE.$SPLIT.txt > output/train.$LOG2C.$DEGREE.$SPLIT.log.txt;
            libsvm_latest/svm-predict output/dev.1.txt output/model.$LOG2C.$DEGREE.$SPLIT.txt output/dev.$LOG2C.$DEGREE.$SPLIT.prediction.txt > output/dev.$LOG2C.$DEGREE.$SPLIT.log.txt;
        done;
    done;
done


# Compute mean and standard deviation
# of classification accuracy.
echo -n > output/dev.results.txt
for F in output/dev.*.log.txt; do
    echo $F $(cat $F) | sed 's;.*\.\(.*\)\.\(.*\)\.\(.*\)\.log.* = \(.*\)%.*;\1 \2 \3 \4;' | grep -v 'classification' >> output/dev.results.txt;
    done

awk '{
acc = $4 / 100;
accuracy_mean[$1" "$2] += acc / 10;
accuracy_var[$1" "$2] += acc ^ 2 / (10 - 1);
}
END {
for (cond in accuracy_mean) {
mean = accuracy_mean[cond];
std = sqrt(accuracy_var[cond] - mean ^ 2 * 10 / (10 - 1));
print cond, mean, std;
}
}' output/dev.results.txt \
| sort -n -k 3 > output/dev.results.summary.txt
