/*
 * First use custom .py script to find unique linear amplification alignments, samtools filter unique alignments, index BAM file and run samtools stats, flagstat and idxstats
 */

include { BEDTOOLS_BAMTOBED           } from "../../modules/nf-core/bedtools/bamtobed/main"
include { FIND_UNIQUE_LA_ALIGNMENTS   } from '../../modules/local/find_unique_la_alignments'
include { SAMTOOLS_VIEW_FILTER_LA     } from '../../modules/local/samtools_view_filter_la'
include { BAM_SORT_STATS_SAMTOOLS } from '../nf-core/bam_sort_stats_samtools/main'
include { SAMTOOLS_SORT      } from "../../modules/nf-core/samtools/sort/main.nf"

workflow DEDUPLICATE_LA {
    take:
    bam            // channel: [ val(meta), [ bam ] ]
    process_target // boolean

    main:
    /*
    * Find unique linear amplification alignments
    */
    ch_bam           = Channel.empty()
    metrics          = Channel.empty()
    ch_versions      = Channel.empty()
    ch_la_duplicates = Channel.empty()

    if( process_target ) {

        SAMTOOLS_SORT ( bam )

        // Convert .bam files to bed to find unique Tn5-ME-A insertion sites
        BEDTOOLS_BAMTOBED ( SAMTOOLS_SORT.out.bam )

        // Use custom .py script to find names of unique alignments
        FIND_UNIQUE_LA_ALIGNMENTS ( BEDTOOLS_BAMTOBED.out.bed )
        ch_la_duplicates    = FIND_UNIQUE_LA_ALIGNMENTS.out.txt
        metrics             = FIND_UNIQUE_LA_ALIGNMENTS.out.metrics
        ch_versions         = ch_versions.mix( FIND_UNIQUE_LA_ALIGNMENTS.out.versions )

        // Subset original .bam file to contain only unique alignments
        SAMTOOLS_VIEW_FILTER_LA (
            bam,
            ch_la_duplicates
        )

        // Return the filtered bam in the channel
        ch_bam = SAMTOOLS_VIEW_FILTER_LA.out.bam

    }
    else { // Split out control files and run only on these

        bam.branch { it ->
            target:  it[0].is_control == false
            control: it[0].is_control == true
        }
        .set { ch_split }
        //ch_split.target | view
        //ch_split.control | view

        SAMTOOLS_SORT (
            ch_split.control
        )        

        // Run .bam to bed on control files only and find unique alignments in control files
        BEDTOOLS_BAMTOBED ( SAMTOOLS_SORT.out.bam )

        // Use custom .py script to find names of unique alignments in control files only
        FIND_UNIQUE_LA_ALIGNMENTS ( BEDTOOLS_BAMTOBED.out.bed )
        ch_la_duplicates    = FIND_UNIQUE_LA_ALIGNMENTS.out.txt
        metrics             = FIND_UNIQUE_LA_ALIGNMENTS.out.metrics
        ch_versions         = ch_versions.mix( FIND_UNIQUE_LA_ALIGNMENTS.out.versions )

        // Subset original .bam file to contain only unique alignments
        SAMTOOLS_VIEW_FILTER_LA (
            ch_split.control,
            ch_la_duplicates
        )
        ch_bam = SAMTOOLS_VIEW_FILTER_LA.out.bam

        // Prevents issues with resume with the branch elements coming in the wrong order
        ch_sorted_targets = ch_split.target
            .toSortedList { row -> row[0].id }
            .flatMap()

        ch_sorted_controls = ch_bam
            .toSortedList { row -> row[0].id }
            .flatMap()

        // Return the filtered control bam file concatenated with the original target bam
        ch_bam    = ch_sorted_targets.concat ( ch_sorted_controls )
    }
    //ch_bam | view

    // Save versions from the SAMTOOLS VIEW process
    ch_versions         = ch_versions.mix( SAMTOOLS_VIEW_FILTER_LA.out.versions )

    /*
    * WORKFLOW: Re sort and index all the bam files + calculate stats
    */
    BAM_SORT_STATS_SAMTOOLS ( 
        ch_bam,
        Channel.empty()
    )

    // Save versions from BAM_SORT_STATS_SAMTOOLS
    ch_versions         = ch_versions.mix( BAM_SORT_STATS_SAMTOOLS.out.versions )

    emit:
    bam      = BAM_SORT_STATS_SAMTOOLS.out.bam        // channel: [ val(meta), [ bam ] ]
    bai      = BAM_SORT_STATS_SAMTOOLS.out.bai        // channel: [ val(meta), [ bai ] ]
    stats    = BAM_SORT_STATS_SAMTOOLS.out.stats      // channel: [ val(meta), [ stats ] ]
    flagstat = BAM_SORT_STATS_SAMTOOLS.out.flagstat   // channel: [ val(meta), [ flagstat ] ]
    idxstats = BAM_SORT_STATS_SAMTOOLS.out.idxstats   // channel: [ val(meta), [ idxstats ] ]
    versions = ch_versions                      // channel: [ versions.yml ]
}
